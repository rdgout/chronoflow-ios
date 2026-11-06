import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthControlTests: XCTestCase {
    @MainActor func testNativeInputsKeepAutoFillSecureEntryAndTouchTargets() async throws {
        struct Fields: View {
            @State var email = ""
            @State var password = ""
            @FocusState var focus: String?
            var body: some View {
                VStack {
                    AuthField(
                        "Email", text: $email, identifier: "email", contentType: .username, keyboard: .emailAddress,
                        focus: $focus
                    ) {}
                    AuthField(
                        "Password", text: $password, secure: true, identifier: "password", contentType: .password,
                        focus: $focus
                    ) {}
                }
            }
        }
        try await FontRegistry.register()
        let host = try AuthTestHost(Fields(), size: CGSize(width: 390, height: 844))
        defer { host.close() }
        try await host.settle()
        func inputs(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(inputs)
        }
        let fields = inputs(host.controller.view)
        XCTAssertEqual(fields.count, 2)
        XCTAssertTrue(fields.contains { $0.isSecureTextEntry && $0.textContentType == .password })
        XCTAssertTrue(fields.contains { $0.keyboardType == .emailAddress && $0.textContentType == .username })
        for field in fields {
            XCTAssertEqual(field.autocorrectionType, .no)
            XCTAssertEqual(field.autocapitalizationType, .none)
        }
    }
    @MainActor func testBusyButtonKeepsItsLabelAndDimensions() async throws {
        try await FontRegistry.register()
        var sizes: [String: CGSize] = [:]
        let view = VStack {
            AuthButton("Sign in", kind: .outline) {}
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    sizes["idle"] = $0
                }
            AuthButton("Sign in", kind: .outline, busy: true) {}
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    sizes["busy"] = $0
                }
        }
        let host = try AuthTestHost(view, size: CGSize(width: 390, height: 844))
        defer { host.close() }
        for _ in 0..<100 where sizes.count != 2 {
            host.window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try XCTUnwrap(sizes["idle"]), try XCTUnwrap(sizes["busy"]))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sizes["busy"]).height, AuthTokens.touch)
    }

}

import AppCore
import Auth
import DataAccess
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordSnapshotTests: XCTestCase {
    @MainActor func testForgotStatesInLeanSnapshotSet() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for (style, language, category) in fixture.authSnapshotVariants {
                print("Forgot snapshots: \(fixture.snapshotName), \(style), \(language), \(category.rawValue)")
                for sent in [false, true] {
                    for state in sent ? [.none] : ForgotPasswordSnapshotState.allCases {
                        var frames: [AuthElement: CGRect] = [:]
                        host.configure(
                            ForgotPasswordView(
                                model: await forgotPasswordSnapshotModel(sent: sent, state: state),
                                measure: { frames[$0] = $1 }),
                            style: style, language: language, category: category)
                        try await host.settle()
                        let suffix =
                            "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(DynamicTypeSize(category).map { String(describing: $0) } ?? category.rawValue)-\(sent ? "sent" : "form")-\(state.rawValue)"
                        let directory = URL(filePath: #filePath).deletingLastPathComponent()
                            .appending(path: "__Snapshots__/Auth/Forgot")
                        let failure = try AuthSnapshotCapture.verify(
                            png: XCTUnwrap(host.image().pngData()),
                            size: fixture.size, scale: fixture.scale,
                            viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                            frames: Dictionary(
                                uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                            required: Set(
                                (Set([AuthElement.brand, .heading, .subtitle, .card])
                                    .union(sent ? [.notice, .openEmail, .backToSignIn] : [.email, .submit]))
                                    .map(
                                        \.rawValue)),
                            reference: directory.appending(path: "\(suffix).png"),
                            record: ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1")
                        if ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" {
                            XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
                        } else if let failure {
                            XCTFail(failure)
                        }
                    }
                }
            }
        }
    }

    @MainActor func testRootCapMakesAX5EqualXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        var expected: SnapshotRaster?
        var expectedFrames: [AuthElement: CGRect] = [:]
        var expectedInput: CGRect?
        var expectedText: CGRect?
        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            var frames: [AuthElement: CGRect] = [:]
            let measure: (AuthElement, CGRect) -> Void = { frames[$0] = $1 }
            host.configure(
                ForgotPasswordView(model: await forgotPasswordSnapshotModel(state: .fieldError), measure: measure),
                category: category)
            try await host.settle()
            let actual = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            let field = try XCTUnwrap(forgotPasswordNativeField(in: host.window))
            let input = field.convert(field.bounds, to: host.window)
            let text = field.convert(field.textRect(forBounds: field.bounds), to: host.window)
            let context =
                "SE, en, light, requested=\(category.rawValue), nativeCategory=\(field.traitCollection.preferredContentSizeCategory.rawValue), resolvedFont=\(String(describing: field.font))"
            XCTAssertNil(
                AuthSnapshotCapture.failure(
                    raster: actual, size: fixture.size, scale: fixture.scale,
                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                    frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                    required: Set(["brand", "heading", "card", "email", "submit"])))
            if let expected {
                XCTAssertEqual(Set(frames.keys), Set(expectedFrames.keys))
                for element in expectedFrames.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    XCTAssertEqual(frames[element], expectedFrames[element], "AX5 frame differs: \(element)")
                }
                XCTAssertTrue(
                    AuthSnapshotCapture.nativeInputRectsMatch(text, try XCTUnwrap(expectedText), scale: host.scale),
                    "AX5 native text rect differs by more than one device pixel: \(text) vs \(String(describing: expectedText)), \(context)"
                )
                XCTAssertTrue(
                    AuthSnapshotCapture.pixelsMatchOutsideNativeInput(
                        actual, expected, input: input, referenceInput: try XCTUnwrap(expectedInput), scale: host.scale),
                    "AX5 native input differs by more than one device pixel, or pixels differ outside its expanded union: \(input) vs \(String(describing: expectedInput)), \(context)"
                )
            } else {
                expected = actual
                expectedFrames = frames
                expectedInput = input
                expectedText = text
            }
        }
    }
}

nonisolated enum ForgotPasswordSnapshotState: String, CaseIterable { case none, fieldError, attempts, server, offline }

@MainActor func forgotPasswordSnapshotModel(sent: Bool = false, state: ForgotPasswordSnapshotState = .none) async
    -> ForgotPasswordModel
{
    let model = ForgotPasswordModel(
        source: MockDataSource(delay: { 0 }, sleep: { _ in }), navigation: AuthNavigation(), email: "rick@example.com")
    if sent {
        await model.submit()
        return model
    }
    switch state {
    case .none: break
    case .fieldError:
        model.form.receive(
            .validation(
                fields: ["email": FieldMessage(key: "Enter a valid email address, like name@example.com.")], status: 422
            ))
    case .attempts: model.form.receive(.throttled(retryAfterSeconds: 60, status: 429))
    case .server: model.form.receive(.server(status: 500))
    case .offline: model.form.receive(.offline)
    }
    return model
}

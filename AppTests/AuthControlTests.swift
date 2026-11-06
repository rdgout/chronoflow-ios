import Auth
import AuthenticationServices
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthControlTests: XCTestCase {
    @MainActor func testLatePasskeyAnchorQueriesUseTheAvailableWindowOrAnEmptyFallback() {
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "app.chronoflow.net")
            .createCredentialAssertionRequest(challenge: Data([1]))
        let staleController = ASAuthorizationController(authorizationRequests: [request])
        var currentWindow: UIWindow? = UIWindow()
        let provider = SystemPasskeyAssertionProvider(anchor: { currentWindow })
        XCTAssertTrue(provider.presentationAnchor(for: staleController) === currentWindow)
        currentWindow = nil
        let fallback = provider.presentationAnchor(for: staleController)
        XCTAssertTrue(fallback.isHidden)
        XCTAssertNil(fallback.windowScene)
    }
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
            XCTAssertTrue(field.text?.isEmpty != false)
            XCTAssertTrue(field.placeholder?.isEmpty != false)
            XCTAssertTrue(field.attributedPlaceholder?.string.isEmpty != false)
            XCTAssertEqual(field.autocorrectionType, .no)
            XCTAssertEqual(field.autocapitalizationType, .none)
        }
    }

    @MainActor func testPasskeyGlyphUsesThePrimaryForegroundInBothAppearances() async throws {
        try await FontRegistry.register()
        for style in [UIUserInterfaceStyle.light, .dark] {
            var frames: [AuthControlPart: CGRect] = [:]
            let host = try AuthTestHost(
                AuthButton("Sign in with a passkey", glyph: .key, measure: { frames[$0] = $1 }) {}
                    .padding(AuthTokens.cardPadding),
                size: CGSize(width: 375, height: 812), style: style)
            defer { host.close() }
            try await host.settle()
            let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            let glyph = try XCTUnwrap(frames[.glyph])
            let expected = try rgb(.primaryForeground, traits: host.controller.traitCollection)
            var matches = 0
            for y in Int(glyph.minY * host.scale)..<Int(glyph.maxY * host.scale) {
                for x in Int(glyph.minX * host.scale)..<Int(glyph.maxX * host.scale) {
                    let offset = (y * raster.width + x) * 4
                    if zip(raster.bytes[offset..<offset + 3], expected).allSatisfy({
                        abs(Double($0) / 255 - $1) < 0.02
                    }) {
                        matches += 1
                    }
                }
            }
            XCTAssertGreaterThan(matches, 5, "Key ink must use primaryForeground in \(style)")
        }
    }

    @MainActor func testBusySpinnerPrecedesGlyphAndLabelInTheCenteredContent() async throws {
        try await FontRegistry.register()
        var frames: [AuthControlPart: CGRect] = [:]
        let host = try AuthTestHost(
            AuthButton("Sign in with a passkey", busy: true, glyph: .key, measure: { frames[$0] = $1 }) {}
                .padding(AuthTokens.cardPadding), size: CGSize(width: 375, height: 812))
        defer { host.close() }
        for _ in 0..<100 where frames.count != 4 {
            host.window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let spinner = try XCTUnwrap(frames[.spinner])
        let glyph = try XCTUnwrap(frames[.glyph])
        let label = try XCTUnwrap(frames[.label])
        let content = try XCTUnwrap(frames[.content])
        XCTAssertEqual(spinner.size, CGSize(width: AuthTokens.icon, height: AuthTokens.icon))
        XCTAssertEqual(glyph.minX - spinner.maxX, AuthTokens.fieldGap, accuracy: 0.5)
        XCTAssertEqual(label.minX - glyph.maxX, AuthTokens.fieldGap, accuracy: 0.5)
        XCTAssertEqual(content.midX, host.window.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(content.minX, spinner.minX, accuracy: 0.5)
        XCTAssertEqual(content.maxX, label.maxX, accuracy: 0.5)
    }

    @MainActor func testFocusedFieldDrawsAnOutsetRingAndCentersItsErrorGlyph() async throws {
        struct Field: View {
            @State var text = ""
            @FocusState var focus: String?
            let measure: (AuthControlPart, CGRect) -> Void
            var body: some View {
                AuthField(
                    "Email", text: $text, error: "Please fill this in.", identifier: "email", contentType: .username,
                    focus: $focus, measure: measure
                ) {}
                .padding(AuthTokens.cardPadding)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(ColorToken.card.color)
                .task { focus = "email" }
            }
        }
        try await FontRegistry.register()
        for style in [UIUserInterfaceStyle.light, .dark] {
            var frames: [AuthControlPart: CGRect] = [:]
            let host = try AuthTestHost(
                Field(measure: { frames[$0] = $1 }), size: CGSize(width: 375, height: 812), style: style)
            defer { host.close() }
            try await host.settle()
            XCTAssertEqual(
                try XCTUnwrap(frames[.errorGlyph]).midY, try XCTUnwrap(frames[.errorText]).midY, accuracy: 0.5)
            let input = try XCTUnwrap(frames[.input])
            let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            for (x, token) in [
                (input.minX - AuthTokens.focusWidth / 2, ColorToken.ring),
                (input.minX + AuthTokens.borderWidth / 2, .destructive),
                (input.minX - AuthTokens.focusWidth - 1, .card),
            ] {
                let offset = (Int(input.midY * host.scale) * raster.width + Int(x * host.scale)) * 4
                let expected = try rgb(token, traits: host.controller.traitCollection)
                for channel in 0..<3 {
                    XCTAssertEqual(Double(raster.bytes[offset + channel]) / 255, expected[channel], accuracy: 0.02)
                }
            }
        }
    }

    @MainActor private func rgb(_ token: ColorToken, traits: UITraitCollection) throws -> [Double] {
        let color = UIColor(token.color).resolvedColor(with: traits).cgColor
        let converted = try XCTUnwrap(
            color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil))
        return try XCTUnwrap(converted.components).prefix(3).map(Double.init)
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

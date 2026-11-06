import Auth
import AuthenticationServices
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthControlTests: XCTestCase {
    @MainActor func testCardShadowMatchesBoardInkInAllEightSignInStates() async throws {
        try await FontRegistry.register()
        let host = try AuthTestHost(EmptyView(), size: AuthShadowBoard.size, scale: AuthShadowBoard.scale)
        defer { host.close() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            host.configure(CfSky(), style: style)
            try await host.settle()
            let sky = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            for banner in [nil] + AuthBannerKind.allCases.map(Optional.some) {
                var frames: [AuthElement: CGRect] = [:]
                let model = authSnapshotModel()
                if let banner { model.form.receive(snapshotFailure(banner)) }
                host.configure(
                    SignInView(model: model, back: {}, guest: {}, measure: { frames[$0] = $1 }), style: style)
                try await host.settle()
                let card = try XCTUnwrap(frames[.card])
                XCTAssertEqual(card.maxY, 728, accuracy: 0.5)
                let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                for sample in AuthShadowBoard.samples {
                    let expected = style == .dark ? sample.dark : sample.light
                    let actual = sample.mean(in: raster)
                    let context = "\(style), \(banner?.rawValue ?? "none"), \(sample.name)"
                    for (actual, expected) in zip(actual, expected) {
                        XCTAssertEqual(actual, expected, accuracy: 4, "Board sRGB: \(context)")
                    }
                    let minimumInk = style == .dark ? sample.minimumDarkInk : sample.minimumLightInk
                    XCTAssertGreaterThanOrEqual(
                        sample.mean(in: sky)[0] - actual[0], minimumInk, "Shadow ink must survive capture: \(context)")
                }
            }
        }
    }

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

    @MainActor func testButtonEndCapsAreSemicirclesWithoutExteriorInk() async throws {
        try await FontRegistry.register()
        for style in [UIUserInterfaceStyle.light, .dark] {
            for scale: CGFloat in [2, 3] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for kind in [AuthButton.Kind.primary, .outline, .footer] {
                        var button = CGRect.zero
                        let host = try AuthTestHost(
                            AuthButton("Sign in", kind: kind) {}
                                .onGeometryChange(for: CGRect.self) {
                                    $0.frame(in: .global)
                                } action: {
                                    button = $0
                                }
                                .padding(AuthTokens.cardPadding)
                                .background(ColorToken.card.color),
                            size: CGSize(width: 375, height: 812), style: style, category: category, scale: scale)
                        defer { host.close() }
                        try await host.settle()
                        XCTAssertEqual(button.width, 375 - 2 * AuthTokens.cardPadding, accuracy: 0.5)
                        XCTAssertGreaterThanOrEqual(button.height, AuthTokens.touch)
                        let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                        let traits = host.controller.traitCollection
                        let backdrop = try rgb(.card, traits: traits)
                        let fill: [Double]
                        switch kind {
                        case .primary: fill = try rgb(.primary, traits: traits)
                        case .outline: fill = try rgb(.background, traits: traits)
                        default:
                            let appearance: TokenAppearance = style == .dark ? .dark : .light
                            let pill = ColorToken.skyCopyBackground.components(for: appearance)
                            let card = ColorToken.card.components(for: appearance)
                            fill = try rgb(
                                XCTUnwrap(
                                    CGColor(
                                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                        components: [
                                            pill.red * pill.alpha + card.red * (1 - pill.alpha),
                                            pill.green * pill.alpha + card.green * (1 - pill.alpha),
                                            pill.blue * pill.alpha + card.blue * (1 - pill.alpha), 1,
                                        ].map { CGFloat($0) })))
                        }
                        let stroke = try rgb(.input, traits: traits)
                        let radius = button.height / 2
                        let margin = 1 / scale
                        var exteriorFailures = 0
                        var interiorFailures = 0
                        var strokePixels = [0, 0]
                        for y in Int((button.minY - 2) * scale)..<Int((button.maxY + 2) * scale) {
                            for x in Int((button.minX - 2) * scale)..<Int((button.maxX + 2) * scale) {
                                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                                let side: Int
                                let centerX: CGFloat
                                if point.x <= button.minX + radius {
                                    side = 0
                                    centerX = button.minX + radius
                                } else if point.x >= button.maxX - radius {
                                    side = 1
                                    centerX = button.maxX - radius
                                } else {
                                    continue
                                }
                                let distance = hypot(point.x - centerX, point.y - button.midY) - radius
                                let offset = (y * raster.width + x) * 4
                                func matches(_ expected: [Double]) -> Bool {
                                    (0..<3).allSatisfy {
                                        abs(Double(raster.bytes[offset + $0]) / 255 - expected[$0]) < 0.02
                                    }
                                }
                                // Exclude one pixel of antialiasing around the analytic circle and its inset stroke.
                                if distance > margin && !matches(backdrop) { exteriorFailures += 1 }
                                if distance < -AuthTokens.borderWidth - margin && !matches(fill) {
                                    interiorFailures += 1
                                }
                                if distance >= -AuthTokens.borderWidth - margin && distance <= margin
                                    && matches(stroke)
                                {
                                    strokePixels[side] += 1
                                }
                            }
                        }
                        let context = "\(kind), \(style), \(scale)x, \(category.rawValue)"
                        XCTAssertEqual(exteriorFailures, 0, "No hairlines or fill outside the circular cap: \(context)")
                        XCTAssertEqual(interiorFailures, 0, "Fill must reach the circular cap: \(context)")
                        if kind == .outline {
                            for count in strokePixels {
                                XCTAssertGreaterThan(count, 5, "Both caps must retain their outline: \(context)")
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor func testCreateAccountLinkUsesDawnTextOnTheCardInBothAppearances() async throws {
        try await FontRegistry.register()
        for style in [UIUserInterfaceStyle.light, .dark] {
            for language in ["en", "nl"] {
                var frames: [AuthElement: CGRect] = [:]
                let host = try AuthTestHost(
                    SignInView(model: authSnapshotModel(), back: {}, guest: {}, measure: { frames[$0] = $1 }),
                    size: CGSize(width: 375, height: 812), style: style, language: language, scale: 3)
                defer { host.close() }
                try await host.settle()
                let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                let label = try XCTUnwrap(frames[.signupLabel])
                let expected = try rgb(.dawnText, traits: host.controller.traitCollection)
                var matches = 0
                for y in Int(label.minY * host.scale)..<Int(label.maxY * host.scale) {
                    for x in Int(label.minX * host.scale)..<Int(label.maxX * host.scale) {
                        let offset = (y * raster.width + x) * 4
                        if zip(raster.bytes[offset..<offset + 3], expected).allSatisfy({
                            abs(Double($0) / 255 - $1) < 0.02
                        }) {
                            matches += 1
                        }
                    }
                }
                XCTAssertGreaterThan(matches, 5, "Create account ink must use dawnText in \(style), \(language)")
            }
        }
    }

    @MainActor func testBusySpinnerPrecedesGlyphAndLabelInTheCenteredContent() async throws {
        try await FontRegistry.register()
        var frames: [AuthControlPart: CGRect] = [:]
        var buttonFrame = CGRect.zero
        let host = try AuthTestHost(
            AuthButton("Sign in with a passkey", busy: true, glyph: .key, measure: { frames[$0] = $1 }) {}
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    buttonFrame = $0
                }
                .padding(AuthTokens.cardPadding), size: CGSize(width: 375, height: 812))
        defer { host.close() }
        var previous: [AuthControlPart: CGRect] = [:]
        var previousButton = CGRect.zero
        var stable = 0
        for _ in 0..<100 {
            host.window.layoutIfNeeded()
            host.controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            let resized = abs(buttonFrame.width - (host.window.bounds.width - 2 * AuthTokens.cardPadding)) <= 0.5
            stable =
                resized && frames.count == 4 && frames == previous && buttonFrame == previousButton ? stable + 1 : 0
            if stable == 3 { break }
            previous = frames
            previousButton = buttonFrame
        }
        XCTAssertEqual(stable, 3, "Wait for geometry after the host window is resized; the spinner keeps animating")
        let spinner = try XCTUnwrap(frames[.spinner])
        let glyph = try XCTUnwrap(frames[.glyph])
        let label = try XCTUnwrap(frames[.label])
        let content = try XCTUnwrap(frames[.content])
        XCTAssertEqual(spinner.size, CGSize(width: AuthTokens.icon, height: AuthTokens.icon))
        XCTAssertEqual(glyph.minX - spinner.maxX, AuthTokens.fieldGap, accuracy: 0.5)
        XCTAssertEqual(label.minX - glyph.maxX, AuthTokens.fieldGap, accuracy: 0.5)
        XCTAssertEqual(buttonFrame.width, host.window.bounds.width - 2 * AuthTokens.cardPadding, accuracy: 0.5)
        XCTAssertEqual(content.midX, buttonFrame.midX, accuracy: 0.5)
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

    @MainActor func testGuestFooterRendersTheBoardTextAndTranslucentPillColors() async throws {
        try await FontRegistry.register()
        for style in [UIUserInterfaceStyle.light, .dark] {
            for language in ["en", "nl"] {
                var frames: [AuthControlPart: CGRect] = [:]
                var button = CGRect.zero
                let host = try AuthTestHost(
                    AuthButton(
                        AuthCopy.string("New here? Plan a trip first", locale: Locale(identifier: language)),
                        kind: .footer, measure: { frames[$0] = $1 }
                    ) {}
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .global)
                    } action: {
                        button = $0
                    }
                    .padding(AuthTokens.cardPadding)
                    .background(ColorToken.skyHorizon.color),
                    size: CGSize(width: 390, height: 844), style: style, language: language)
                defer { host.close() }
                try await host.settle()
                let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                let appearance: TokenAppearance = style == .dark ? .dark : .light
                let pill = ColorToken.skyCopyBackground.components(for: appearance)
                let sky = ColorToken.skyHorizon.components(for: appearance)
                let composite = try XCTUnwrap(
                    CGColor(
                        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                        components: [
                            pill.red * pill.alpha + sky.red * (1 - pill.alpha),
                            pill.green * pill.alpha + sky.green * (1 - pill.alpha),
                            pill.blue * pill.alpha + sky.blue * (1 - pill.alpha), 1,
                        ].map { CGFloat($0) }))
                let expectedPill = try rgb(composite)
                let offset =
                    (Int(button.midY * host.scale) * raster.width + Int((button.minX + button.height / 2) * host.scale))
                    * 4
                for channel in 0..<3 {
                    XCTAssertEqual(Double(raster.bytes[offset + channel]) / 255, expectedPill[channel], accuracy: 0.02)
                }
                let label = try XCTUnwrap(frames[.label])
                let expectedText = try rgb(.skyCopy, traits: host.controller.traitCollection)
                var matches = 0
                for y in Int(label.minY * host.scale)..<Int(label.maxY * host.scale) {
                    for x in Int(label.minX * host.scale)..<Int(label.maxX * host.scale) {
                        let offset = (y * raster.width + x) * 4
                        if zip(raster.bytes[offset..<offset + 3], expectedText).allSatisfy({
                            abs(Double($0) / 255 - $1) < 0.02
                        }) {
                            matches += 1
                        }
                    }
                }
                XCTAssertGreaterThan(matches, 5, "Footer ink must use skyCopy in \(style), \(language)")
            }
        }
    }

    @MainActor private func rgb(_ token: ColorToken, traits: UITraitCollection) throws -> [Double] {
        try rgb(UIColor(token.color).resolvedColor(with: traits).cgColor)
    }

    @MainActor private func rgb(_ color: CGColor) throws -> [Double] {
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

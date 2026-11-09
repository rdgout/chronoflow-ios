import DesignSystem
import UIKit
import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    @MainActor private var variants: [(String, XCUIDevice.Appearance, Bool)] {
        [XCUIDevice.Appearance.light, .dark].flatMap { appearance in
            ["en", "nl"].map { ($0, appearance, false) }
        } + [("en", .light, true)]
    }

    @MainActor func testSignInInLeanAuditMatrix() async throws { try await auditSignInOrTwoFactor(mode: 0) }
    @MainActor func testTwoFactorCodeInLeanAuditMatrix() async throws { try await auditSignInOrTwoFactor(mode: 1) }
    @MainActor func testTwoFactorRecoveryInLeanAuditMatrix() async throws { try await auditSignInOrTwoFactor(mode: 2) }
    @MainActor func testForgotFormInLeanAuditMatrix() async throws { try await auditForgot(state: "form") }
    @MainActor func testForgotSentInLeanAuditMatrix() async throws { try await auditForgot(state: "sent") }
    @MainActor func testForgotFieldInLeanAuditMatrix() async throws { try await auditForgot(state: "field") }
    @MainActor func testForgotServerInLeanAuditMatrix() async throws { try await auditForgot(state: "server") }
    @MainActor func testForgotThrottleInLeanAuditMatrix() async throws { try await auditForgot(state: "throttle") }
    @MainActor func testForgotOfflineInLeanAuditMatrix() async throws { try await auditForgot(state: "offline") }

    @MainActor func testResetFormInLeanAuditMatrix() async throws { try await auditReset(state: "form") }
    @MainActor func testResetPasswordInLeanAuditMatrix() async throws { try await auditReset(state: "password") }
    @MainActor func testResetConfirmationInLeanAuditMatrix() async throws {
        try await auditReset(state: "confirmation")
    }
    @MainActor func testResetExpiredInLeanAuditMatrix() async throws { try await auditReset(state: "expired") }
    @MainActor func testResetDoneInLeanAuditMatrix() async throws { try await auditReset(state: "done") }
    @MainActor func testResetServerInLeanAuditMatrix() async throws { try await auditReset(state: "server") }
    @MainActor func testResetThrottleInLeanAuditMatrix() async throws { try await auditReset(state: "throttle") }
    @MainActor func testResetOfflineInLeanAuditMatrix() async throws { try await auditReset(state: "offline") }

    @MainActor private func auditReset(state: String) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            if state == "expired" {
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = "https://app.chronoflow.net/reset-password"
            }
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_RESET_FAILURE"] = state
            }
            app.launch()
            defer { app.terminate() }
            if state == "expired" {
                XCTAssertTrue(app.textFields["forgot.email"].waitForExistence(timeout: 12))
            } else {
                openResetFromMockMail(app)
                if state != "form" {
                    fillReset(
                        app, password: state == "password" ? "short" : "NewPassword123!",
                        confirmation: state == "confirmation"
                            ? "different" : state == "password" ? "short" : "NewPassword123!")
                    if state == "done" {
                        XCTAssertTrue(app.buttons["reset.continue"].waitForExistence(timeout: 6))
                    } else {
                        let finished = XCTNSPredicateExpectation(
                            predicate: NSPredicate { _, _ in app.secureTextFields["reset.password"].isEnabled },
                            object: nil)
                        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 6), .completed)
                    }
                }
            }
            let identifiers =
                state == "expired"
                ? ["auth.back", "forgot.email", "forgot.submit", "forgot.back"]
                : state == "done"
                    ? ["auth.back", "reset.continue"]
                    : ["auth.back", "reset.password", "reset.confirmation", "reset.submit"]
                        + (["server", "throttle"].contains(state) ? ["auth.banner"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), reset-\(state)", appearance: appearance,
                xxLarge: xxLarge)
        }
    }

    @MainActor private func auditSignInOrTwoFactor(mode: Int) async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for (language, appearance, xxLarge) in variants {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launch()
            defer { app.terminate() }
            AuthUIFlow.openSignIn(app)
            if mode > 0 {
                AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
                XCTAssertTrue(app.textFields["two-factor.code"].waitForExistence(timeout: 8))
                let keyboardHidden = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
                if mode == 2 {
                    AuthUIFlow.reveal(app.buttons["two-factor.toggle"], in: app)
                    app.buttons["two-factor.toggle"].tap()
                }
            }
            auditControls(
                app,
                identifiers: mode == 0
                    ? [
                        "auth.back", "sign-in.passkey", "sign-in.email", "sign-in.password",
                        "sign-in.submit", "sign-in.forgot", "sign-in.signup", "sign-in.guest",
                    ]
                    : [
                        "auth.back", mode == 2 ? "two-factor.recovery_code" : "two-factor.code",
                        "two-factor.submit", "two-factor.toggle",
                    ],
                language: "\(language), \(xxLarge ? "xxLarge" : "default")", appearance: appearance, xxLarge: xxLarge)
        }
    }

    @MainActor private func auditForgot(state: String) async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for (language, appearance, xxLarge) in variants {
            try DeviceAppearance.set(appearance)
            let app = launchForgotApp(
                language: language, xxLarge: xxLarge, failure: state, offline: state == "offline")
            defer { app.terminate() }
            openForgot(app)
            if state != "form" {
                let field = app.textFields["forgot.email"]
                field.tap()
                field.typeText(state == "field" ? "invalid\n" : "unknown@example.com\n")
                if state == "sent" {
                    XCTAssertTrue(AuthUIFlow.control("forgot.notice", in: app).waitForExistence(timeout: 6))
                } else if state == "server" || state == "throttle" {
                    XCTAssertTrue(
                        AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 6),
                        "Missing Forgot \(state) banner: \(language), \(appearance), xxLarge=\(xxLarge)")
                } else {
                    let received = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in
                            field.isEnabled && field.value(forKey: "hasKeyboardFocus") as? Bool == true
                        }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [received], timeout: 6), .completed)
                }
            }
            let identifiers =
                state == "sent"
                ? ["auth.back", "forgot.notice", "forgot.open-email", "forgot.back"]
                : ["auth.back", "forgot.email", "forgot.submit"]
                    + (["server", "throttle"].contains(state) ? ["auth.banner"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), \(state), \(xxLarge ? "xxLarge" : "default")",
                appearance: appearance, xxLarge: xxLarge, forgotBannerState: state)
        }
    }

    @MainActor private func auditControls(
        _ app: XCUIApplication, identifiers: [String], language: String, appearance: XCUIDevice.Appearance,
        xxLarge: Bool, forgotBannerState: String? = nil
    ) {
        var auditedPositions: [[CGRect]] = []
        for identifier in identifiers {
            let control = AuthUIFlow.control(identifier, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 3), identifier)
            AuthUIFlow.reveal(control, in: app)
            let position = [
                AuthUIFlow.control("auth.subtitle", in: app).frame,
                AuthUIFlow.scroll(in: app).frame,
                app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame : .zero,
            ]
            guard !auditedPositions.contains(position) else { continue }
            auditedPositions.append(position)
            audit(
                app, language: language, appearance: appearance, stage: identifier, xxLarge: xxLarge,
                forgotBannerState: forgotBannerState)
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String, xxLarge: Bool,
        forgotBannerState: String?
    ) {
        var bannerMinimum: Double?
        var bannerFrame: CGRect?
        var brandFrame: CGRect?
        var bannerMeasurement = "not eligible"
        if ["server", "throttle"].contains(forgotBannerState ?? ""), app.scrollViews["forgot.scroll"].exists {
            let banner = AuthUIFlow.control("auth.banner", in: app)
            if banner.exists {
                bannerFrame = banner.frame
                let brand = AuthUIFlow.control("auth.brand", in: app)
                if brand.exists { brandFrame = brand.frame }
                (bannerMinimum, bannerMeasurement) = textContrast(
                    banner, in: app, appearance: appearance, xxLarge: xxLarge, banner: true)
                print("Forgot banner contrast [\(language), \(appearance), \(stage)]: \(bannerMeasurement)")
                if let bannerMinimum {
                    XCTAssertGreaterThanOrEqual(bannerMinimum, 4.5, bannerMeasurement)
                }
            }
        }
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
                let boardContrast = Self.isBoardContrast(
                    identifier: issue.element?.identifier, auditType: issue.auditType)
                var minimum: Double?
                var measurement = "not eligible"
                if issue.auditType == .contrast, let element = issue.element, element.identifier == "auth.subtitle" {
                    (minimum, measurement) = self.textContrast(
                        element, in: app, appearance: appearance, xxLarge: xxLarge)
                }
                let ignored =
                    boardContrast
                    || Self.isMeasuredSubtitleContrast(
                        identifier: issue.element?.identifier, auditType: issue.auditType, minimum: minimum)
                    || Self.isMeasuredForgotBannerContrast(
                        identifier: issue.element?.identifier, frame: issue.element?.frame, bannerFrame: bannerFrame,
                        brandFrame: brandFrame, auditType: issue.auditType,
                        state: forgotBannerState, minimum: bannerMinimum)
                let message = """
                    Auth accessibility [\(language), \(appearance), \(stage)] \
                    auditType=\(issue.auditType) identifier=\(issue.element?.identifier ?? "<nil>") \
                    label=\(issue.element?.label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                    frame=\(String(describing: issue.element?.frame)) bannerFrame=\(String(describing: bannerFrame)) \
                    brandFrame=\(String(describing: brandFrame)) \
                    boardContrast=\(boardContrast) ignored=\(ignored) subtitleMinimum=\(minimum.map { "\($0):1" } ?? "unmeasurable")
                    \(measurement)
                    bannerMinimum=\(bannerMinimum.map { "\($0):1" } ?? "unmeasurable")
                    \(bannerMeasurement)
                    """
                print(message)
                let attachment = XCTAttachment(string: message)
                attachment.lifetime = .keepAlways
                self.add(attachment)
                if !ignored { XCTFail(message) }
                return ignored
            }
        } catch {
            XCTFail("Auth accessibility audit failed [\(language), \(appearance), \(stage)]: \(error)")
        }
    }

    @MainActor private func textContrast(
        _ element: XCUIElement, in app: XCUIApplication, appearance: XCUIDevice.Appearance, xxLarge: Bool,
        banner: Bool = false
    ) -> (Double?, String) {
        let identifier = banner ? "auth.banner" : "auth.subtitle"
        let scrolls = app.scrollViews.containing(.any, identifier: identifier).allElementsBoundByIndex
        let matches = scrolls.filter { scroll in
            let elements = scroll.descendants(matching: .any).matching(identifier: identifier)
            return elements.count == 1 && elements.element.frame == element.frame
                && elements.element.label == element.label
        }
        guard banner || element.elementType == .staticText, matches.count == 1, let scroll = matches.first else {
            return (nil, "No unique \(identifier) in the current auth screen")
        }
        let appFrame = app.frame
        var frame = element.frame.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        if banner {
            frame = frame.insetBy(dx: AuthTokens.bannerHorizontal, dy: AuthTokens.bannerVertical)
            let glyph = AuthTokens.bannerGlyph + AuthTokens.bannerGap
            frame.origin.x += glyph
            frame.size.width -= glyph
        }
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            .offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(identifier) contrast source"
        attachment.lifetime = .keepAlways
        add(attachment)
        do {
            let raster = try SnapshotRaster(png: screenshot.pngRepresentation)
            let scale = CGFloat(raster.width) / appFrame.width
            guard scale.isFinite, scale > 0, abs(CGFloat(raster.height) / scale - appFrame.height) < 1 else {
                return (nil, "Screenshot and app bounds disagree: \(raster.width)×\(raster.height), app=\(appFrame)")
            }
            let traits = UITraitCollection {
                $0.userInterfaceStyle = appearance == .dark ? .dark : .light
                $0.preferredContentSizeCategory = xxLarge ? .extraExtraLarge : .large
            }
            let token: ColorToken = banner ? .cardForeground : .skyTitle
            let typography = banner ? Typography.authHint : Typography.authBody
            guard
                let rgb = UIColor(token.color).resolvedColor(with: traits).cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components
            else { return (nil, "Cannot convert \(identifier) ink to sRGB") }
            let font = typography.uiFont(compatibleWith: traits)
            guard let leading = typography.lineHeight else { return (nil, "Missing \(identifier) leading") }
            let measurement = RenderedTextContrast.measure(
                raster: raster, frame: frame, scale: scale,
                lineHeight: leading * font.pointSize / typography.size,
                text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
            let lines = measurement.lines.enumerated().map { index, line in
                "line=\(index + 1), frame=\(line.frame), ratio=\(line.minimum)...\(line.maximum):1, ink=\(line.ink)"
            }.joined(separator: "\n")
            return (
                measurement.minimum,
                "\(identifier)=\(frame), viewport=\(viewport), scale=\(scale), tokens=\(banner ? "cardForeground/authErrorBackground" : "skyTitle/cf-sky"), minimum=\(measurement.minimum.map { "\($0):1" } ?? "unmeasurable"), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines)\n\(lines)"
            )
        } catch {
            return (nil, "\(identifier) screenshot measurement failed: \(error)")
        }
    }

    @MainActor private static func isMeasuredSubtitleContrast(
        identifier: String?, auditType: XCUIAccessibilityAuditType, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == "auth.subtitle", let minimum else { return false }
        return minimum.isFinite && minimum >= 4.5
    }

    // Audit frames are Double; element frames round-trip through Float, so exact containment misses by ~1e-6.
    private static let frameTolerance: CGFloat = 0.01

    @MainActor private static func isMeasuredForgotBannerContrast(
        identifier: String?, frame: CGRect?, bannerFrame: CGRect?, brandFrame: CGRect? = nil,
        auditType: XCUIAccessibilityAuditType,
        state: String?, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, ["server", "throttle"].contains(state ?? ""),
            identifier == nil || identifier == "" || identifier == "auth.banner",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let bannerFrame, !bannerFrame.isEmpty, !bannerFrame.isInfinite,
            let minimum
        else { return false }
        let unattributedBrand =
            (identifier == nil || identifier == "") && brandFrame?.isInfinite == false
            && brandFrame?.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame) == true
        return minimum.isFinite && minimum >= 4.5
            && (bannerFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame) || unattributedBrand)
    }

    @MainActor func testBannerExceptionRequiresMatchingGeometryAndPassingPixels() {
        let banner = CGRect(x: 30, y: 300, width: 330, height: 64)
        let title = CGRect(x: 78, y: 312, width: 262, height: 20)
        let brand = CGRect(x: 130, y: 63, width: 140, height: 24)
        let wordmark = CGRect(x: 158, y: 63, width: 112, height: 24)
        for state in ["server", "throttle"] {
            for identifier: String? in [nil, "", "auth.banner"] {
                for frame in [banner, title] {
                    XCTAssertTrue(
                        Self.isMeasuredForgotBannerContrast(
                            identifier: identifier, frame: frame, bannerFrame: banner,
                            auditType: .contrast, state: state, minimum: 4.5))
                }
            }
        }
        for identifier: String? in [nil, ""] {
            XCTAssertTrue(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: wordmark, bannerFrame: banner, brandFrame: brand,
                    auditType: .contrast, state: "server", minimum: 14.884))
        }
        for identifier: String? in [nil, "", "auth.banner", "auth.brand", "auth.back"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: wordmark, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: 12.420))
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: title.offsetBy(dx: 0, dy: 100), bannerFrame: banner,
                    brandFrame: brand,
                    auditType: .contrast, state: "server", minimum: 12.420))
        }
        for identifier in ["auth.brand", "auth.banner", "auth.back"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: wordmark, bannerFrame: banner, brandFrame: brand,
                    auditType: .contrast, state: "server", minimum: 12.420))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: minimum))
        }
        for state: String? in [nil, "form", "sent", "field", "offline", "sign-in"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: state, minimum: 10))
        }
        for identifier in ["auth.banner.new", "auth.back", "forgot.email", "forgot.submit", "auth.subtitle"] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: title, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: 10))
        }
        for invalid: CGRect? in [
            nil, .zero, .null, .infinite, CGRect(x: 30, y: 270, width: 330, height: 40),
            CGRect(x: 40, y: 100, width: 44, height: 44),
        ] {
            for identifier: String? in [nil, "", "auth.banner"] {
                XCTAssertFalse(
                    Self.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: invalid, bannerFrame: banner,
                        auditType: .contrast, state: "server", minimum: 10))
                XCTAssertFalse(
                    Self.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: title, bannerFrame: invalid,
                        auditType: .contrast, state: "server", minimum: 10))
            }
        }
        for type: XCUIAccessibilityAuditType in [
            .textClipped, .dynamicType, .hitRegion, .trait, .all,
            [.contrast, .textClipped],
        ] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    auditType: type, state: "server", minimum: 10))
        }
    }

    @MainActor private static func isBoardContrast(identifier: String?, auditType: XCUIAccessibilityAuditType) -> Bool {
        // Board boundary contrast is accepted, OQ 33 (user 2026-11-06); text ratios remain pinned.
        auditType == .contrast && identifier == "sign-in.guest"
    }

    @MainActor func testAuditAllowsOnlyTheGuestFooterBoardContrastPair() {
        XCTAssertTrue(Self.isBoardContrast(identifier: "sign-in.guest", auditType: .contrast))
        for type: XCUIAccessibilityAuditType in [
            .textClipped, .dynamicType, .hitRegion, .trait, .all, [.contrast, .textClipped],
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: "sign-in.guest", auditType: type))
        }
        for identifier in [
            nil, "", "sign-in", "sign-in.submit", "sign-in.passkey", "sign-in.email", "sign-in.password",
            "sign-in.forgot", "sign-in.signup", "two-factor.code", "two-factor.recovery_code",
            "two-factor.submit", "two-factor.toggle", "forgot.email", "forgot.submit", "forgot.notice",
            "forgot.open-email", "forgot.back", "auth.back", "auth.heading", "auth.banner", "welcome.plan",
            "sign-in.guest.new", "auth.subtitle",
        ] {
            XCTAssertFalse(Self.isBoardContrast(identifier: identifier, auditType: .contrast))
        }
    }

    @MainActor func testSubtitleExceptionRequiresAnExactContrastIssueAndAMeasuredPassingMinimum() {
        for minimum in [4.5, 10.8] {
            XCTAssertTrue(
                Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: .contrast, minimum: minimum))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: .contrast, minimum: minimum))
        }
        for identifier in [nil, "", "auth.subtitle.new", "auth.heading", "two-factor.toggle", "sign-in.submit"] {
            XCTAssertFalse(Self.isMeasuredSubtitleContrast(identifier: identifier, auditType: .contrast, minimum: 10.8))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .hitRegion, .trait, .all, [.contrast, .textClipped]] {
            XCTAssertFalse(Self.isMeasuredSubtitleContrast(identifier: "auth.subtitle", auditType: type, minimum: 10.8))
        }
    }
}

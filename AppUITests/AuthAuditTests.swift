import DesignSystem
import UIKit
import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    @MainActor func testSignInAndBothTwoFactorModesInBothLanguagesAppearancesAndSizes() async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for language in ["en", "nl"] {
            for appearance in [XCUIDevice.Appearance.light, .dark] {
                for xxLarge in [false, true] {
                    try DeviceAppearance.set(appearance)
                    let app = XCUIApplication()
                    app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
                    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
                    app.launch()
                    defer { app.terminate() }
                    AuthUIFlow.openSignIn(app)
                    let context = "\(language), \(xxLarge ? "xxLarge" : "default")"
                    auditControls(
                        app,
                        identifiers: [
                            "auth.back", "sign-in.passkey", "sign-in.email", "sign-in.password",
                            "sign-in.submit", "sign-in.forgot", "sign-in.signup", "sign-in.guest",
                        ],
                        language: context, appearance: appearance, xxLarge: xxLarge)
                    AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
                    XCTAssertTrue(app.textFields["two-factor.code"].waitForExistence(timeout: 8))
                    let keyboardHidden = XCTNSPredicateExpectation(
                        predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists }, object: nil)
                    XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)
                    for recovery in [false, true] {
                        if recovery {
                            AuthUIFlow.reveal(app.buttons["two-factor.toggle"], in: app)
                            app.buttons["two-factor.toggle"].tap()
                        }
                        auditControls(
                            app,
                            identifiers: [
                                "auth.back", recovery ? "two-factor.recovery_code" : "two-factor.code",
                                "two-factor.submit", "two-factor.toggle",
                            ],
                            language: context, appearance: appearance, xxLarge: xxLarge)
                    }
                }
            }
        }
    }

    @MainActor func testForgotStatesInBothLanguagesAppearancesAndSizes() async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for language in ["en", "nl"] {
            for appearance in [XCUIDevice.Appearance.light, .dark] {
                for xxLarge in [false, true] {
                    for state in ["form", "sent", "field", "server", "throttle", "offline"] {
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
                            app, identifiers: identifiers, language: "\(language), \(state)", appearance: appearance,
                            xxLarge: xxLarge)
                    }
                }
            }
        }
    }

    @MainActor private func auditControls(
        _ app: XCUIApplication, identifiers: [String], language: String, appearance: XCUIDevice.Appearance,
        xxLarge: Bool
    ) {
        for identifier in identifiers {
            let control = AuthUIFlow.control(identifier, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 3), identifier)
            AuthUIFlow.reveal(control, in: app)
            audit(app, language: language, appearance: appearance, stage: identifier, xxLarge: xxLarge)
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String, xxLarge: Bool
    ) {
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
                let boardContrast = Self.isBoardContrast(
                    identifier: issue.element?.identifier, auditType: issue.auditType)
                var minimum: Double?
                var measurement = "not eligible"
                if issue.auditType == .contrast, let element = issue.element, element.identifier == "auth.subtitle" {
                    (minimum, measurement) = self.subtitleContrast(
                        element, in: app, appearance: appearance, xxLarge: xxLarge)
                }
                let ignored =
                    boardContrast
                    || Self.isMeasuredSubtitleContrast(
                        identifier: issue.element?.identifier, auditType: issue.auditType, minimum: minimum)
                let message = """
                    Auth accessibility [\(language), \(appearance), \(stage)] \
                    auditType=\(issue.auditType) identifier=\(issue.element?.identifier ?? "<nil>") \
                    label=\(issue.element?.label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                    boardContrast=\(boardContrast) ignored=\(ignored) subtitleMinimum=\(minimum.map { "\($0):1" } ?? "unmeasurable")
                    \(measurement)
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

    @MainActor private func subtitleContrast(
        _ element: XCUIElement, in app: XCUIApplication, appearance: XCUIDevice.Appearance, xxLarge: Bool
    ) -> (Double?, String) {
        let scrolls = app.scrollViews.containing(.staticText, identifier: "auth.subtitle").allElementsBoundByIndex
        let matches = scrolls.filter { scroll in
            let subtitles = scroll.staticTexts.matching(identifier: "auth.subtitle")
            return subtitles.count == 1 && subtitles.element.frame == element.frame
                && subtitles.element.label == element.label
        }
        guard element.elementType == .staticText, matches.count == 1, let scroll = matches.first else {
            return (nil, "No unique subtitle in the current auth screen")
        }
        let appFrame = app.frame
        let frame = element.frame.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            .offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Auth subtitle contrast source"
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
            guard
                let rgb = UIColor(ColorToken.skyTitle.color).resolvedColor(with: traits).cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components
            else { return (nil, "Cannot convert subtitle ink to sRGB") }
            let font = Typography.authBody.uiFont(compatibleWith: traits)
            guard let leading = Typography.authBody.lineHeight else { return (nil, "Missing subtitle leading") }
            let measurement = RenderedTextContrast.measure(
                raster: raster, frame: frame, scale: scale,
                lineHeight: leading * font.pointSize / Typography.authBody.size,
                text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
            let lines = measurement.lines.enumerated().map { index, line in
                "line=\(index + 1), frame=\(line.frame), ratio=\(line.minimum)...\(line.maximum):1, ink=\(line.ink)"
            }.joined(separator: "\n")
            return (
                measurement.minimum,
                "subtitle=\(frame), viewport=\(viewport), scale=\(scale), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines)\n\(lines)"
            )
        } catch {
            return (nil, "Subtitle screenshot measurement failed: \(error)")
        }
    }

    @MainActor private static func isMeasuredSubtitleContrast(
        identifier: String?, auditType: XCUIAccessibilityAuditType, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == "auth.subtitle", let minimum else { return false }
        return minimum.isFinite && minimum >= 4.5
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

import CoreText
import DesignSystem
import UIKit
import XCTest

nonisolated final class AuthAuditTests: XCTestCase {
    @MainActor private func variants() -> [(String, XCUIDevice.Appearance, Bool)] {
        guard ProcessInfo.processInfo.environment["AUTH_AUDIT_FULL"] == "1" else {
            return [("en", .light, false)]
        }
        return [
            ("en", .light, false), ("nl", .light, false),
            ("en", .dark, false), ("nl", .dark, false),
            ("en", .light, true),
        ]
    }

    @MainActor func testSignInAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 0)
    }
    @MainActor func testTwoFactorCodeAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 1)
    }
    @MainActor func testTwoFactorRecoveryAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 2)
    }
    @MainActor func testForgotFormAudit() async throws {
        try await auditForgot(state: "form")
    }
    @MainActor func testForgotSentAudit() async throws {
        try await auditForgot(state: "sent")
    }
    @MainActor func testForgotFieldAudit() async throws {
        try await auditForgot(state: "field")
    }
    @MainActor func testForgotServerAudit() async throws {
        try await auditForgot(state: "server")
    }
    @MainActor func testForgotThrottleAudit() async throws {
        try await auditForgot(state: "throttle")
    }
    @MainActor func testForgotOfflineAudit() async throws {
        try await auditForgot(state: "offline")
    }

    @MainActor func testResetFormAudit() async throws {
        try await auditReset(state: "form")
    }
    @MainActor func testResetPasswordAudit() async throws {
        try await auditReset(state: "password")
    }
    @MainActor func testResetConfirmationAudit() async throws {
        try await auditReset(state: "confirmation")
    }
    @MainActor func testResetExpiredAudit() async throws {
        try await auditReset(state: "expired")
    }
    @MainActor func testResetDoneAudit() async throws {
        try await auditReset(state: "done")
    }
    @MainActor func testResetServerAudit() async throws {
        try await auditReset(state: "server")
    }
    @MainActor func testResetThrottleAudit() async throws {
        try await auditReset(state: "throttle")
    }
    @MainActor func testResetOfflineAudit() async throws {
        try await auditReset(state: "offline")
    }

    @MainActor private func auditReset(state: String) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants() {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            configureAudit(app, screen: "reset", state: state)
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
                    submitPrefilled(app, screen: "reset", state: state)
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
                    ? ["reset.continue"]
                    : ["reset.password", "reset.confirmation", "reset.submit"]
                        + (["server", "throttle"].contains(state) ? ["auth.banner"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), reset-\(state)", appearance: appearance,
                xxLarge: xxLarge)
        }
    }

    @MainActor func testSignUpFormAudit() async throws {
        try await auditSignUp(state: "form")
    }
    @MainActor func testSignUpEmptyAudit() async throws {
        try await auditSignUp(state: "empty")
    }
    @MainActor func testSignUpEmailAudit() async throws {
        try await auditSignUp(state: "email")
    }
    @MainActor func testSignUpTakenAudit() async throws {
        try await auditSignUp(state: "taken")
    }
    @MainActor func testSignUpPasswordAudit() async throws {
        try await auditSignUp(state: "password")
    }
    @MainActor func testSignUpConfirmationAudit() async throws {
        try await auditSignUp(state: "confirmation")
    }
    @MainActor func testSignUpVisibleAudit() async throws {
        try await auditSignUp(state: "visible")
    }
    @MainActor func testSignUpServerAudit() async throws {
        try await auditSignUp(state: "server")
    }
    @MainActor func testSignUpThrottleAudit() async throws {
        try await auditSignUp(state: "throttle")
    }
    @MainActor func testSignUpOfflineAudit() async throws {
        try await auditSignUp(state: "offline")
    }

    @MainActor private func auditSignUp(state: String) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants() {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            configureAudit(app, screen: "sign-up", state: state)
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_SIGNUP_FAILURE"] = state
            }
            app.launch()
            defer { app.terminate() }
            openSignUp(app)
            if state == "visible" {
                AuthUIFlow.reveal(app.switches["sign-up.visibility"], in: app)
                app.switches["sign-up.visibility"].tap()
            } else if state != "form" {
                submitPrefilled(app, screen: "sign-up", state: state)
            }
            auditControls(
                app,
                identifiers: [
                    "auth.back", "sign-up.name", "sign-up.email", "sign-up.password", "sign-up.confirmation",
                    "sign-up.visibility", "sign-up.submit", "sign-up.consent", "sign-up.back",
                ] + (["taken", "server", "throttle"].contains(state) ? ["auth.banner"] : []),
                language: "\(language), sign-up-\(state)", appearance: appearance, xxLarge: xxLarge)
        }
    }

    @MainActor func testVerifyWaitingAudit() async throws {
        try await auditVerify(state: "waiting")
    }
    @MainActor func testVerifyCountdownAudit() async throws {
        try await auditVerify(state: "countdown")
    }
    @MainActor func testVerifyFailedAudit() async throws {
        try await auditVerify(state: "failed")
    }
    @MainActor func testVerifyServerAudit() async throws {
        try await auditVerify(state: "server")
    }
    @MainActor func testVerifyThrottleAudit() async throws {
        try await auditVerify(state: "throttle")
    }
    @MainActor func testVerifyOfflineAudit() async throws {
        try await auditVerify(state: "offline")
    }
    @MainActor func testVerifySignOutErrorAudit() async throws {
        try await auditVerify(state: "signOutError")
    }

    @MainActor func testVerifyFailedServerAudit() async throws {
        try await auditVerify(state: "failedServer")
    }
    @MainActor func testVerifyFailedThrottleAudit() async throws {
        try await auditVerify(state: "failedThrottle")
    }
    @MainActor func testVerifyFailedOfflineAudit() async throws {
        try await auditVerify(state: "failedOffline")
    }

    @MainActor private func auditVerify(state: String) async throws {
        try await FontRegistry.register()
        let previous = XCUIDevice.shared.appearance
        defer { XCUIDevice.shared.appearance = previous }
        for (language, appearance, xxLarge) in variants() {
            try DeviceAppearance.set(appearance)
            let app = XCUIApplication()
            app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["CF_AUTH_TEST_VERIFY_STATE"] = state
            configureAudit(app, screen: "sign-up", state: "verify")
            if state.hasPrefix("failed") {
                app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = tamperedVerificationURL()
            }
            app.launch()
            defer { app.terminate() }
            if state.hasPrefix("failed") {
                AuthUIFlow.openSignIn(app)
                AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
            } else {
                openSignUp(app)
                submitPrefilled(app, screen: "sign-up", state: "verify")
            }
            let first = app.buttons[state.hasPrefix("failed") ? "verify.retry" : "verify.open-email"]
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            AuthUIFlow.waitUntilEnabled(first)
            if ["countdown", "throttle", "server", "offline", "failedServer", "failedThrottle", "failedOffline"]
                .contains(state)
            {
                let resend = app.buttons["verify.resend"]
                let enabled = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in resend.isEnabled }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 6), .completed)
                AuthUIFlow.reveal(resend, in: app)
                resend.tap()
                if state != "offline" && state != "failedOffline" {
                    XCTAssertTrue(AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 6))
                }
                if state == "countdown" {
                    XCUIDevice.shared.press(.home)
                    app.activate()
                }
            } else if state == "signOutError" {
                let back = app.buttons["verify.different-email"]
                AuthUIFlow.reveal(back, in: app)
                back.tap()
                XCTAssertTrue(AuthUIFlow.control("verify.sign-out-error", in: app).waitForExistence(timeout: 6))
            }
            let identifiers =
                (state.hasPrefix("failed")
                    ? ["auth.back", "verify.retry", "verify.resend"]
                    : ["auth.back", "verify.open-email", "verify.resend", "verify.different-email"])
                + (["countdown", "throttle"].contains(state) ? ["verify.countdown"] : [])
                + (["server", "throttle", "failedServer", "failedThrottle"].contains(state) ? ["auth.banner"] : [])
                + (state == "signOutError" ? ["verify.sign-out-error"] : [])
            auditControls(
                app, identifiers: identifiers, language: "\(language), verify-\(state)", appearance: appearance,
                xxLarge: xxLarge)
        }
    }

    @MainActor private func auditSignInOrTwoFactor(mode: Int) async throws {
        try await FontRegistry.register()
        let device = XCUIDevice.shared
        let previous = device.appearance
        defer { device.appearance = previous }
        for (language, appearance, xxLarge) in variants() {
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
        for (language, appearance, xxLarge) in variants() {
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

    @MainActor private func configureAudit(_ app: XCUIApplication, screen: String, state: String) {
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] = screen
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] = state
    }

    @MainActor private func submitPrefilled(_ app: XCUIApplication, screen: String, state: String) {
        let button = app.buttons["\(screen).submit"]
        AuthUIFlow.reveal(button, in: app)
        button.tap()
        if ["taken", "server", "throttle"].contains(state) {
            XCTAssertTrue(
                AuthUIFlow.control("auth.banner", in: app).waitForExistence(timeout: 6),
                "Expected \(screen) \(state) banner after submitting the prefilled form")
        } else if !["empty", "verify", "done"].contains(state) {
            let password = app.secureTextFields["\(screen).password"]
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    guard password.exists, password.isEnabled, let value = password.value as? String else {
                        return false
                    }
                    return value.isEmpty || value == password.placeholderValue
                }, object: nil)
            XCTAssertEqual(
                XCTWaiter.wait(for: [finished], timeout: 6), .completed,
                "Expected \(screen) \(state) request to finish and clear its prefilled password")
        }
    }

    @MainActor private func auditControls(
        _ app: XCUIApplication, identifiers: [String], language: String, appearance: XCUIDevice.Appearance,
        xxLarge: Bool, forgotBannerState: String? = nil
    ) {
        AuthUIFlow.dismissKeyboard(in: app)
        let identifiers = ["auth.brand", "auth.heading", "auth.subtitle"] + identifiers
        let scroll = AuthUIFlow.scroll(in: app)
        var controls: [String: XCUIElement] = [:]
        for identifier in identifiers {
            let matches = scroll.descendants(matching: .any).matching(identifier: identifier)
            guard matches.firstMatch.waitForExistence(timeout: 3), matches.count == 1 else {
                XCTFail("Expected one accessibility element for \(identifier); found \(matches.count)")
                return
            }
            controls[identifier] = matches.element
        }
        let initialFrames = controls.mapValues(\.frame)
        let ordered = identifiers.sorted { initialFrames[$0]!.minY < initialFrames[$1]!.minY }
        var pending = Set(identifiers)
        for identifier in ordered where pending.contains(identifier) {
            let control = controls[identifier]!
            AuthUIFlow.reveal(control, in: app, scroll: scroll)
            do {
                _ = try UIWait.stableFrames([control, scroll], timeout: 3)
            } catch {
                XCTFail("Audit frames did not settle for \(identifier): \(error)")
                return
            }
            let contentViewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            let navigationViewport = AuthUIFlow.viewport(
                in: app, scrollFrame: scroll.frame, includingNavigationBar: true)
            let viewport = identifier == "auth.back" ? navigationViewport : contentViewport
            let frames = controls.mapValues(\.frame)
            guard AuthScrollGesture.fullyVisible(frames[identifier]!, in: viewport) else {
                XCTFail(
                    "Expected fully visible \(identifier) before auditing: frame=\(control.frame), viewport=\(viewport)"
                )
                return
            }
            let visible = pending.filter {
                AuthScrollGesture.fullyVisible(
                    frames[$0]!, in: $0 == "auth.back" ? navigationViewport : contentViewport)
            }
            for identifier in visible {
                XCTAssertTrue(
                    controls[identifier]!.isHittable, "Expected reachable \(identifier) in audit viewport \(viewport)")
            }
            audit(
                app, language: language, appearance: appearance, stage: identifier, xxLarge: xxLarge,
                forgotBannerState: forgotBannerState, controls: controls)
            pending.subtract(visible)
        }
        XCTAssertTrue(pending.isEmpty, "Controls never audited fully inside the viewport: \(pending.sorted())")
    }

    @MainActor private func audit(
        _ app: XCUIApplication, language: String, appearance: XCUIDevice.Appearance, stage: String, xxLarge: Bool,
        forgotBannerState: String?, controls: [String: XCUIElement]
    ) {
        guard let source = captureAudit(app, controls: controls, context: "\(language), \(appearance), \(stage)") else {
            return
        }
        if ["server", "throttle"].contains(forgotBannerState ?? ""), app.scrollViews["forgot.scroll"].exists {
            let (minimum, measurement) = textContrast(
                "auth.banner", capture: source, appearance: appearance, xxLarge: xxLarge, banner: true)
            print("Forgot banner contrast [\(language), \(appearance), \(stage)]: \(measurement)")
            if let minimum {
                XCTAssertGreaterThanOrEqual(minimum, 4.5, measurement)
            }
        }
        if let backFrame = source.frames["sign-up.back"],
            AuthScrollGesture.fullyVisible(backFrame, in: source.viewport)
        {
            let (minimum, measurement) = textContrast(
                "sign-up.back", capture: source, appearance: appearance, xxLarge: xxLarge, footer: true)
            print("Sign-up footer contrast [\(language), \(appearance), \(stage)]: \(measurement)")
            if let minimum {
                XCTAssertGreaterThanOrEqual(minimum, 4.5, measurement)
            } else {
                XCTFail("Unmeasurable sign-up.back contrast [\(language), \(appearance), \(stage)]: \(measurement)")
            }
        }
        do {
            try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
                let element = issue.element
                let identifier = element?.identifier
                let frame = element?.frame
                let enabled = element?.isEnabled
                let elementType = element?.elementType
                let disabledContrast = AuthAuditPolicy.isDisabledContrast(
                    isContrast: issue.auditType == .contrast, isEnabled: enabled)
                let boardContrast = Self.isBoardContrast(identifier: identifier, auditType: issue.auditType)
                var ignored = disabledContrast || boardContrast
                var diagnostics = ""
                if issue.auditType == .contrast, !ignored {
                    guard
                        let capture = self.captureAudit(
                            app, controls: controls,
                            context: "\(language), \(appearance), \(stage), \(identifier ?? "<nil>")")
                    else { return true }
                    if Self.isDeferredControlContrast(
                        auditType: issue.auditType, frame: frame, viewport: capture.viewport,
                        controlFrames: Array(capture.frames.values))
                    {
                        return true
                    }
                    var subtitleMinimum: Double?
                    var subtitleMeasurement = "not eligible"
                    if identifier == "auth.subtitle", elementType == .staticText,
                        AuthAuditPolicy.contains(frame, in: capture.frames["auth.subtitle"])
                    {
                        (subtitleMinimum, subtitleMeasurement) = self.textContrast(
                            "auth.subtitle", capture: capture, appearance: appearance, xxLarge: xxLarge)
                    }
                    var brandMinimum: Double?
                    var brandMeasurement = "not eligible"
                    let brandFrame = capture.frames["auth.brand"]
                    if identifier == nil || identifier == "", AuthAuditPolicy.contains(frame, in: brandFrame) {
                        (brandMinimum, brandMeasurement) = self.textContrast(
                            "auth.brand", capture: capture, appearance: appearance, xxLarge: xxLarge, brand: true)
                    }
                    var backMinimum: Double?
                    var backMeasurement = "not eligible"
                    let backFrame = capture.frames["sign-up.back"]
                    if identifier == "sign-up.back", AuthAuditPolicy.contains(frame, in: backFrame) {
                        (backMinimum, backMeasurement) = self.textContrast(
                            "sign-up.back", capture: capture, appearance: appearance, xxLarge: xxLarge, footer: true)
                    }
                    var bannerMinimum: Double?
                    var bannerMeasurement = "not eligible"
                    let bannerFrame = capture.frames["auth.banner"]
                    if ["server", "throttle"].contains(forgotBannerState ?? ""),
                        app.scrollViews["forgot.scroll"].exists,
                        AuthAuditPolicy.contains(frame, in: bannerFrame)
                    {
                        (bannerMinimum, bannerMeasurement) = self.textContrast(
                            "auth.banner", capture: capture, appearance: appearance, xxLarge: xxLarge, banner: true)
                    }
                    ignored =
                        Self.isMeasuredSubtitleContrast(
                            identifier: identifier, auditType: issue.auditType, minimum: subtitleMinimum)
                        || Self.isMeasuredSignUpBackContrast(
                            identifier: identifier, frame: frame, backFrame: backFrame,
                            auditType: issue.auditType, minimum: backMinimum)
                        || Self.isMeasuredBrandContrast(
                            identifier: identifier, frame: frame, brandFrame: brandFrame,
                            auditType: issue.auditType, minimum: brandMinimum)
                        || Self.isMeasuredForgotBannerContrast(
                            identifier: identifier, frame: frame, bannerFrame: bannerFrame,
                            auditType: issue.auditType, state: forgotBannerState, minimum: bannerMinimum)
                    diagnostics = """
                        auditedFrames=\(capture.frames)
                        subtitleMinimum=\(subtitleMinimum.map { "\($0):1" } ?? "unmeasurable")
                        \(subtitleMeasurement)
                        brandMinimum=\(brandMinimum.map { "\($0):1" } ?? "unmeasurable")
                        \(brandMeasurement)
                        backMinimum=\(backMinimum.map { "\($0):1" } ?? "unmeasurable")
                        \(backMeasurement)
                        bannerMinimum=\(bannerMinimum.map { "\($0):1" } ?? "unmeasurable")
                        \(bannerMeasurement)
                        """
                }
                let message = """
                    Auth accessibility [\(language), \(appearance), \(stage)] \
                    auditType=\(issue.auditType) identifier=\(identifier ?? "<nil>") \
                    label=\(element?.label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                    frame=\(String(describing: frame)) enabled=\(String(describing: enabled)) \
                    disabledContrast=\(disabledContrast) boardContrast=\(boardContrast) ignored=\(ignored)
                    \(diagnostics)
                    """
                print(message)
                let attachment = XCTAttachment(string: message)
                attachment.lifetime = .keepAlways
                self.add(attachment)
                if !ignored { XCTFail(message) }
                // Record one attributed failure ourselves; XCTest otherwise adds an unlabelled duplicate.
                return true
            }
        } catch {
            XCTFail("Auth accessibility audit failed [\(language), \(appearance), \(stage)]: \(error)")
        }
    }

    private struct AuditCapture {
        let raster: SnapshotRaster
        let appFrame: CGRect
        let viewport: CGRect
        let frames: [String: CGRect]
        let labels: [String: String]
    }

    @MainActor private func captureAudit(
        _ app: XCUIApplication, controls: [String: XCUIElement], context: String
    ) -> AuditCapture? {
        let scroll = AuthUIFlow.scroll(in: app)
        let measuredControls = controls.filter {
            ["auth.brand", "auth.subtitle", "auth.banner", "sign-up.back"].contains($0.key)
        }
        for _ in 0..<3 {
            let appFrame = app.frame
            let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            let frames = controls.mapValues(\.frame)
            let labels = measuredControls.mapValues(\.label)
            let screenshot = app.screenshot()
            // The audit may move the scroll view; never pair its new frames with an earlier raster.
            guard AuthAuditPolicy.sameFrames(frames, controls.mapValues(\.frame)), appFrame == app.frame,
                viewport == AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame),
                labels == measuredControls.mapValues(\.label)
            else { continue }
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Auth audit source [\(context)]"
            attachment.lifetime = .keepAlways
            add(attachment)
            do {
                return AuditCapture(
                    raster: try SnapshotRaster(png: screenshot.pngRepresentation), appFrame: appFrame,
                    viewport: viewport, frames: frames, labels: labels)
            } catch {
                XCTFail("Cannot decode auth audit screenshot [\(context)]: \(error)")
                return nil
            }
        }
        XCTFail("Auth audit geometry changed during screenshot capture [\(context)]")
        return nil
    }

    @MainActor private func textContrast(
        _ identifier: String, capture: AuditCapture, appearance: XCUIDevice.Appearance, xxLarge: Bool,
        banner: Bool = false, brand: Bool = false, footer: Bool = false
    ) -> (Double?, String) {
        guard let elementFrame = capture.frames[identifier], let label = capture.labels[identifier],
            AuthScrollGesture.fullyVisible(elementFrame, in: capture.viewport)
        else { return (nil, "\(identifier) not fully visible in the audited screenshot") }
        let raster = capture.raster
        let appFrame = capture.appFrame
        var frame = elementFrame.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        if banner {
            frame = frame.insetBy(dx: AuthTokens.bannerHorizontal, dy: AuthTokens.bannerVertical)
            let glyph = AuthTokens.bannerGlyph + AuthTokens.bannerGap
            frame.origin.x += glyph
            frame.size.width -= glyph
        }
        if brand {
            let glyph = AuthTokens.moon + AuthTokens.brandGap
            frame.origin.x += glyph
            frame.size.width -= glyph
        }
        let viewport = capture.viewport.offsetBy(dx: -appFrame.minX, dy: -appFrame.minY)
        let scale = CGFloat(raster.width) / appFrame.width
        guard scale.isFinite, scale > 0, abs(CGFloat(raster.height) / scale - appFrame.height) < 1 else {
            return (nil, "Screenshot and app bounds disagree: \(raster.width)×\(raster.height), app=\(appFrame)")
        }
        let traits = UITraitCollection {
            $0.userInterfaceStyle = appearance == .dark ? .dark : .light
            $0.preferredContentSizeCategory = xxLarge ? .extraExtraLarge : .large
        }
        let token: ColorToken = banner ? .cardForeground : footer ? .skyCopy : .skyTitle
        let typography =
            banner
            ? Typography.authHint : brand ? Typography.authBrand : footer ? Typography.authLabel : Typography.authBody
        guard
            let rgb = UIColor(token.color).resolvedColor(with: traits).cgColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?.components
        else { return (nil, "Cannot convert \(identifier) ink to sRGB") }
        let font = typography.uiFont(compatibleWith: traits)
        guard let leading = typography.lineHeight else { return (nil, "Missing \(identifier) leading") }
        if footer {
            guard AuthScrollGesture.fullyVisible(frame, in: viewport) else {
                return (nil, "sign-up.back must be fully visible before measuring")
            }
            frame = frame.insetBy(dx: AuthTokens.spacer, dy: 0)
            let ratio = font.pointSize / typography.size
            let text = NSAttributedString(
                string: label, attributes: [.font: font, .kern: typography.tracking * ratio])
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var location = 0
            var lines = 0
            while location < text.length {
                location += max(1, CTTypesetterSuggestLineBreak(typesetter, location, frame.width))
                lines += 1
            }
            let height = CGFloat(lines) * leading * ratio
            guard height <= frame.height - 2 * AuthTokens.fieldGap + Self.frameTolerance else {
                return (nil, "Cannot fit sign-up.back text lines inside the measured button: \(height), \(frame)")
            }
            frame = CGRect(x: frame.minX, y: frame.midY - height / 2, width: frame.width, height: height)
        }
        let measurement = RenderedTextContrast.measure(
            raster: raster, frame: frame, scale: scale,
            lineHeight: leading * font.pointSize / typography.size,
            text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
        let lines = measurement.lines.enumerated().map { index, line in
            "line=\(index + 1), frame=\(line.frame), ratio=\(line.minimum)...\(line.maximum):1, ink=\(line.ink)"
        }.joined(separator: "\n")
        return (
            measurement.minimum,
            "\(identifier)=\(frame), viewport=\(viewport), scale=\(scale), tokens=\(banner ? "cardForeground/authErrorBackground" : footer ? "skyCopy/skyCopyBackground" : "skyTitle/cf-sky"), minimum=\(measurement.minimum.map { "\($0):1" } ?? "unmeasurable"), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines)\n\(lines)"
        )
    }

    @MainActor private static func isMeasuredSignUpBackContrast(
        identifier: String?, frame: CGRect?, backFrame: CGRect?, auditType: XCUIAccessibilityAuditType,
        minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == "sign-up.back", let frame, let backFrame,
            let minimum, minimum.isFinite, minimum >= 4.5
        else { return false }
        return AuthAuditPolicy.contains(frame, in: backFrame)
    }

    @MainActor func testSignUpFooterExceptionRequiresItsOwnFrameAndPassingPixels() {
        let button = CGRect(x: 16, y: 700, width: 358, height: 48)
        XCTAssertTrue(
            Self.isMeasuredSignUpBackContrast(
                identifier: "sign-up.back", frame: button, backFrame: button, auditType: .contrast, minimum: 4.5))
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: button, backFrame: button, auditType: .contrast, minimum: minimum
                ))
        }
        for identifier: String? in [nil, "", "sign-up.submit", "auth.subtitle", "sign-up.back.new"] {
            XCTAssertFalse(
                Self.isMeasuredSignUpBackContrast(
                    identifier: identifier, frame: button, backFrame: button, auditType: .contrast, minimum: 10))
        }
        for frame: CGRect? in [nil, .zero, .null, .infinite, button.offsetBy(dx: 0, dy: 20)] {
            XCTAssertFalse(
                Self.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: frame, backFrame: button, auditType: .contrast, minimum: 10))
            XCTAssertFalse(
                Self.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: button, backFrame: frame, auditType: .contrast, minimum: 10))
        }
        XCTAssertFalse(
            Self.isMeasuredSignUpBackContrast(
                identifier: "sign-up.back", frame: button, backFrame: button, auditType: .textClipped, minimum: 10))
    }

    @MainActor private static func isMeasuredSubtitleContrast(
        identifier: String?, auditType: XCUIAccessibilityAuditType, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == "auth.subtitle", let minimum else { return false }
        return minimum.isFinite && minimum >= 4.5
    }

    // Audit frames are Double; element frames round-trip through Float, so exact containment misses by ~1e-6.
    private static let frameTolerance = AuthAuditPolicy.frameTolerance

    @MainActor func testDisabledExceptionRequiresOnlyContrastAndAnExplicitDisabledState() {
        XCTAssertTrue(AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: false))
        for enabled: Bool? in [nil, true] {
            XCTAssertFalse(AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: enabled))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .hitRegion, .trait, .all, [.contrast, .textClipped]] {
            XCTAssertFalse(AuthAuditPolicy.isDisabledContrast(isContrast: type == .contrast, isEnabled: false))
        }
    }

    @MainActor private static func isDeferredControlContrast(
        auditType: XCUIAccessibilityAuditType, frame: CGRect?, viewport: CGRect, controlFrames: [CGRect]
    ) -> Bool {
        guard auditType == .contrast, let frame, !frame.isEmpty, !frame.isInfinite,
            !viewport.isEmpty, !viewport.isInfinite,
            !viewport.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        else { return false }
        // Each scheduled control is revealed and audited in full before this screen finishes.
        return controlFrames.contains {
            !$0.isEmpty && !$0.isInfinite && $0.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
        }
    }

    @MainActor private static func isMeasuredBrandContrast(
        identifier: String?, frame: CGRect?, brandFrame: CGRect?, auditType: XCUIAccessibilityAuditType,
        minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, identifier == nil || identifier == "",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let brandFrame, !brandFrame.isEmpty, !brandFrame.isInfinite,
            let minimum, minimum.isFinite, minimum >= 4.5
        else { return false }
        return brandFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    @MainActor func testWordmarkExceptionRequiresItsOwnGeometryAndPassingPixels() {
        let brand = CGRect(x: 130, y: 63, width: 140, height: 24)
        let wordmark = CGRect(x: 158, y: 62.999999, width: 112.000001, height: 24.000002)
        for identifier: String? in [nil, ""] {
            XCTAssertTrue(
                Self.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: 4.5))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: minimum))
        }
        for frame: CGRect? in [nil, .zero, .null, .infinite, wordmark.offsetBy(dx: 0, dy: 1)] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: frame, brandFrame: brand, auditType: .contrast, minimum: 15))
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: frame, auditType: .contrast, minimum: 15))
        }
        for identifier in ["auth.brand", "auth.banner", "sign-up.submit", "auth.subtitle"] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, auditType: .contrast, minimum: 15))
        }
        for type: XCUIAccessibilityAuditType in [.textClipped, .hitRegion, .trait, .all, [.contrast, .textClipped]] {
            XCTAssertFalse(
                Self.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: brand, auditType: type, minimum: 15))
        }
    }

    @MainActor func testOnlyClippedScheduledControlContrastCanWaitForItsReveal() {
        let viewport = CGRect(x: 0, y: 47, width: 390, height: 500)
        let button = CGRect(x: 36, y: 530, width: 318, height: 44)
        XCTAssertTrue(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport, controlFrames: [button]))
        for frame: CGRect? in [nil, .zero, .null, .infinite, button.offsetBy(dx: 0, dy: 50)] {
            XCTAssertFalse(
                Self.isDeferredControlContrast(
                    auditType: .contrast, frame: frame, viewport: viewport, controlFrames: [button]))
        }
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport, controlFrames: []))
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .contrast, frame: button, viewport: viewport.insetBy(dx: 0, dy: -100),
                controlFrames: [button]))
        XCTAssertFalse(
            Self.isDeferredControlContrast(
                auditType: .textClipped, frame: button, viewport: viewport, controlFrames: [button]))
    }

    @MainActor private static func isMeasuredForgotBannerContrast(
        identifier: String?, frame: CGRect?, bannerFrame: CGRect?,
        auditType: XCUIAccessibilityAuditType,
        state: String?, minimum: Double?
    ) -> Bool {
        guard auditType == .contrast, ["server", "throttle"].contains(state ?? ""),
            identifier == nil || identifier == "" || identifier == "auth.banner",
            let frame, !frame.isEmpty, !frame.isInfinite,
            let bannerFrame, !bannerFrame.isEmpty, !bannerFrame.isInfinite,
            let minimum
        else { return false }
        return minimum.isFinite && minimum >= 4.5
            && bannerFrame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(frame)
    }

    @MainActor func testBannerExceptionRequiresMatchingGeometryAndPassingPixels() {
        let banner = CGRect(x: 30, y: 300, width: 330, height: 64)
        let title = CGRect(x: 78, y: 312, width: 262, height: 20)
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
        for frame in [title.offsetBy(dx: 0, dy: 100), CGRect(x: 158, y: 63, width: 112, height: 24)] {
            XCTAssertFalse(
                Self.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: frame, bannerFrame: banner,
                    auditType: .contrast, state: "server", minimum: 14.884))
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

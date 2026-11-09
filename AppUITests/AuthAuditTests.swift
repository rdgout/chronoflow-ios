import CoreText
import DesignSystem
import UIKit
import XCTest

nonisolated class AuthAuditCase: ScreenTestCase {
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

    @MainActor fileprivate func auditReset(state: String) async throws {
        try await FontRegistry.register()
        for (language, appearance, xxLarge) in variants() {
            let app = ScreenTestApp.makeApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language, xxLarge: xxLarge) + [
                    "-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light",
                ]
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            configureAudit(app, screen: "reset", state: state)
            if state == "expired" {
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = "https://app.chronoflow.net/reset-password"
            }
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_RESET_FAILURE"] = state
            }
            app.launchMeasured()
            if state == "expired" {
                XCTAssertTrue(app.textFields["forgot.email"].waitUntil(.exists, timeout: 12))
            } else {
                openResetFromMockMail(app)
                if state != "form" {
                    submitPrefilled(app, screen: "reset", state: state)
                    if state == "done" {
                        XCTAssertTrue(app.buttons["reset.continue"].waitUntil(.exists, timeout: 6))
                    } else {
                        let finished = { () -> Bool in
                            app.secureTextFields["reset.password"].isEnabled
                        }
                        XCTAssertTrue(UIWait.until(timeout: 6, condition: finished))
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

    @MainActor fileprivate func auditSignUp(state: String) async throws {
        try await FontRegistry.register()
        for (language, appearance, xxLarge) in variants() {
            let app = ScreenTestApp.makeApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language, xxLarge: xxLarge) + [
                    "-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light",
                ]
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            configureAudit(app, screen: "sign-up", state: state)
            if ["server", "throttle", "offline"].contains(state) {
                app.launchEnvironment["CF_AUTH_TEST_SIGNUP_FAILURE"] = state
            }
            app.launchMeasured()
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

    @MainActor fileprivate func auditVerify(state: String) async throws {
        try await FontRegistry.register()
        for (language, appearance, xxLarge) in variants() {
            let app = ScreenTestApp.makeApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language, xxLarge: xxLarge) + [
                    "-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light",
                ]
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["CF_AUTH_TEST_VERIFY_STATE"] = state
            app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
            if state.hasPrefix("failed") {
                app.launchEnvironment["CF_AUTH_TEST_LINK"] = tamperedVerificationURL()
            }
            AuthUIFlow.launchSignedIn(app, walkthroughSeen: true)
            let first = app.buttons[state.hasPrefix("failed") ? "verify.retry" : "verify.open-email"]
            XCTAssertTrue(first.waitUntil(.exists, timeout: 12))
            AuthUIFlow.waitUntilEnabled(first)
            if ["countdown", "throttle", "server", "offline", "failedServer", "failedThrottle", "failedOffline"]
                .contains(state)
            {
                let resend = app.buttons["verify.resend"]
                let enabled = { () -> Bool in
                    resend.isEnabled
                }
                XCTAssertTrue(UIWait.until(timeout: 6, condition: enabled))
                AuthUIFlow.reveal(resend, in: app)
                resend.tap()
                if state != "offline" && state != "failedOffline" {
                    XCTAssertTrue(AuthUIFlow.control("auth.banner", in: app).waitUntil(.exists, timeout: 6))
                }
                if state == "countdown" {
                    XCUIDevice.shared.press(.home)
                    app.activate()
                }
            } else if state == "signOutError" {
                let back = app.buttons["verify.different-email"]
                AuthUIFlow.reveal(back, in: app)
                back.tap()
                XCTAssertTrue(AuthUIFlow.control("verify.sign-out-error", in: app).waitUntil(.exists, timeout: 6))
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

    @MainActor fileprivate func auditSignInOrTwoFactor(mode: Int) async throws {
        try await FontRegistry.register()
        for (language, appearance, xxLarge) in variants() {
            let app = ScreenTestApp.makeApplication()
            app.launchArguments =
                AuthUIFlow.arguments(language: language, xxLarge: xxLarge) + [
                    "-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light",
                ]
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
            configureAudit(app, screen: mode > 0 ? "two-factor" : "sign-in", state: "form")
            app.launchMeasured()
            if mode == 0 { AuthUIFlow.openSignIn(app) }
            if mode > 0 {
                XCTAssertTrue(app.textFields["two-factor.code"].waitUntil(.exists, timeout: 12))
                let keyboardHidden = { () -> Bool in
                    !app.keyboards.firstMatch.exists
                }
                XCTAssertTrue(UIWait.until(timeout: 5, condition: keyboardHidden))
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

    @MainActor fileprivate func auditForgot(state: String) async throws {
        try await FontRegistry.register()
        for (language, appearance, xxLarge) in variants() {
            let app = launchForgotApp(
                language: language, xxLarge: xxLarge, failure: state, offline: state == "offline",
                appearance: appearance, seedScreen: true)
            openForgot(app)
            if state != "form" {
                let field = app.textFields["forgot.email"]
                field.tap()
                field.typeText(state == "field" ? "invalid\n" : "unknown@example.com\n")
                if state == "sent" {
                    XCTAssertTrue(AuthUIFlow.control("forgot.notice", in: app).waitUntil(.exists, timeout: 6))
                } else if state == "server" || state == "throttle" {
                    XCTAssertTrue(
                        AuthUIFlow.control("auth.banner", in: app).waitUntil(.exists, timeout: 6),
                        "Missing Forgot \(state) banner: \(language), \(appearance), xxLarge=\(xxLarge)")
                } else {
                    let received = { () -> Bool in
                        field.isEnabled && field.value(forKey: "hasKeyboardFocus") as? Bool == true
                    }
                    XCTAssertTrue(UIWait.until(timeout: 6, condition: received))
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
                AuthUIFlow.control("auth.banner", in: app).waitUntil(.exists, timeout: 6),
                "Expected \(screen) \(state) banner after submitting the prefilled form")
        } else if !["empty", "verify", "done"].contains(state) {
            let password = app.secureTextFields["\(screen).password"]
            let finished = { () -> Bool in
                guard password.exists, password.isEnabled, let value = password.value as? String else {
                    return false
                }
                return value.isEmpty || value == password.placeholderValue
            }
            XCTAssertTrue(
                UIWait.until(timeout: 6, condition: finished),
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
            let matches = AuthUIFlow.query(identifier, in: scroll)
            let element = matches.firstMatch
            guard element.waitUntil(.exists, timeout: 3) else {
                XCTFail("Missing accessibility element for \(identifier)")
                return
            }
            let count = matches.count
            guard count == 1 else {
                XCTFail("Expected one accessibility element for \(identifier); found \(count)")
                return
            }
            controls[identifier] = element
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
        // The combined audit resizes text while checking clipping, invalidating contrast capture geometry.
        for types in [XCUIAccessibilityAuditType.contrast, .all.subtracting([.dynamicType, .contrast])] {
            do {
                _ = try UIWait.stableFrames(Array(controls.values) + [AuthUIFlow.scroll(in: app)], timeout: 6)
            } catch {
                XCTFail("Audit layout did not settle [\(language), \(appearance), \(stage), \(types)]: \(error)")
                return
            }
            audit(
                app, types: types, language: language, appearance: appearance, stage: stage, xxLarge: xxLarge,
                forgotBannerState: forgotBannerState, controls: controls)
        }
    }

    @MainActor private func audit(
        _ app: XCUIApplication, types: XCUIAccessibilityAuditType, language: String,
        appearance: XCUIDevice.Appearance, stage: String, xxLarge: Bool,
        forgotBannerState: String?, controls: [String: XCUIElement]
    ) {
        guard
            let source = captureAudit(
                app, controls: controls, context: "\(language), \(appearance), \(stage), \(types)")
        else {
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
            try app.performAccessibilityAudit(for: types) { issue in
                let element = issue.element
                let identifier = element?.identifier
                let frame = element?.frame
                let enabled = element?.isEnabled
                let elementType = element?.elementType
                let disabledContrast = AuthAuditPolicy.isDisabledContrast(
                    isContrast: issue.auditType == .contrast, isEnabled: enabled)
                let boardContrast = AuthAuditPolicy.isBoardContrast(
                    identifier: identifier, isContrast: issue.auditType == .contrast)
                var ignored = disabledContrast || boardContrast
                var diagnostics = ""
                if issue.auditType == .contrast, !ignored {
                    guard
                        let capture = self.captureAudit(
                            app, controls: controls,
                            context: "\(language), \(appearance), \(stage), \(identifier ?? "<nil>")")
                    else { return true }
                    if AuthAuditPolicy.isDeferredControlContrast(
                        isContrast: issue.auditType == .contrast, frame: frame, viewport: capture.viewport,
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
                        AuthAuditPolicy.isMeasuredSubtitleContrast(
                            identifier: identifier, isContrast: issue.auditType == .contrast, minimum: subtitleMinimum)
                        || AuthAuditPolicy.isMeasuredSignUpBackContrast(
                            identifier: identifier, frame: frame, backFrame: backFrame,
                            isContrast: issue.auditType == .contrast, minimum: backMinimum)
                        || AuthAuditPolicy.isMeasuredBrandContrast(
                            identifier: identifier, frame: frame, brandFrame: brandFrame,
                            isContrast: issue.auditType == .contrast, minimum: brandMinimum)
                        || AuthAuditPolicy.isMeasuredForgotBannerContrast(
                            identifier: identifier, frame: frame, bannerFrame: bannerFrame,
                            isContrast: issue.auditType == .contrast, state: forgotBannerState, minimum: bannerMinimum)
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
            guard height <= frame.height - 2 * AuthTokens.fieldGap + AuthAuditPolicy.frameTolerance else {
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

}

nonisolated final class AuthAuditTests: AuthAuditCase {
    @MainActor func testSignInAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 0)
    }
    @MainActor func testTwoFactorCodeAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 1)
    }
    @MainActor func testTwoFactorRecoveryAudit() async throws {
        try await auditSignInOrTwoFactor(mode: 2)
    }
}

nonisolated final class ForgotAuditTests: AuthAuditCase {
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
}

nonisolated final class ResetAuditTests: AuthAuditCase {
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
}

nonisolated final class SignUpAuditTests: AuthAuditCase {
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
}

nonisolated final class VerifyAuditTests: AuthAuditCase {
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
}

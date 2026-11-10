import XCTest

@MainActor enum AuthUIFlow {
    enum Account: String { case demo, twofactor }

    static func launchScreen(
        _ screen: String, state: String = "form", language: String = "en", xxLarge: Bool = false,
        extraEnv: [String: String] = [:], extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = arguments(language: language, xxLarge: xxLarge) + extraArguments
        app.launchEnvironment = extraEnv
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] = screen
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] = state
        app.launchMeasured()
        requireSeededScreen(screen, in: app)
        return app
    }

    static func requireSeededScreen(_ screen: String, in app: XCUIApplication) {
        guard app.launchEnvironment["CF_UI_TEST_PROFILE"] == "screen",
            app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] == screen
        else {
            XCTFail("Expected mandatory CF_AUTH_TEST_AUDIT_SCREEN=\(screen) seed")
            return
        }
        let first: XCUIElement
        switch screen {
        case "sign-in": first = app.textFields["sign-in.email"]
        case "sign-up": first = app.textFields["sign-up.name"]
        case "forgot": first = app.textFields["forgot.email"]
        case "reset":
            first =
                app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] == "expired"
                ? app.textFields["forgot.email"] : app.secureTextFields["reset.password"]
        case "two-factor": first = app.textFields["two-factor.code"]
        default:
            XCTFail("Unknown auth screen seed: \(screen)")
            return
        }
        XCTAssertTrue(first.waitUntil(.exists, timeout: 5), "Seed did not open \(screen)")
    }

    static func launchSignedIn(
        _ app: XCUIApplication, walkthroughSeen: Bool, account: Account = .demo, extraEnv: [String: String] = [:]
    ) {
        if app.launchArguments.isEmpty { app.launchArguments = arguments() }
        if app.launchEnvironment["CF_AUTH_TEST_ID"] == nil {
            app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        }
        if app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] == nil {
            app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = walkthroughSeen ? "1" : "0"
        }
        app.launchEnvironment["CF_AUTH_TEST_SIGNED_IN"] = account.rawValue
        app.launchEnvironment.merge(extraEnv) { _, value in value }
        app.launchMeasured()
    }

    static func arguments(language: String = "en", xxLarge: Bool = false) -> [String] {
        var result = [
            "-cf.reduceMotion", "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "nl" ? "nl_NL" : "en_US",
        ]
        result += [
            "-UIPreferredContentSizeCategoryName", xxLarge ? "UICTContentSizeCategoryXXL" : "UICTContentSizeCategoryL",
        ]
        return result
    }

    static func waitUntilEnabled(_ element: XCUIElement) {
        let enabled = { () -> Bool in
            element.exists && element.isEnabled
        }
        XCTAssertTrue(UIWait.until(timeout: 5, condition: enabled), "Expected enabled \(element.identifier)")
    }

    static func openSignIn(_ app: XCUIApplication) {
        let button = app.buttons["welcome.signIn"]
        let ready = { () -> Bool in
            button.exists || app.textFields["sign-in.email"].exists
        }
        XCTAssertTrue(
            UIWait.until(timeout: 5, condition: ready), "Expected Welcome Sign in or the Sign in email field")
        if app.textFields["sign-in.email"].exists { return }
        reveal(button, in: app, scroll: app.scrollViews.containing(.button, identifier: "welcome.signIn").element)
        button.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitUntil(.exists, timeout: 4),
            "Expected sign-in.email after Welcome Sign in"
        )
        XCTAssertFalse(app.images["launch.opening"].exists, "Expected the splash to be dismissed before Sign in")
    }

    static func signIn(_ app: XCUIApplication, email: String) {
        let field = app.textFields["sign-in.email"]
        reveal(field, in: app)
        field.tap()
        if let previous = field.value as? String, previous != field.placeholderValue, !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(email + "\n")
        XCTAssertEqual(field.value as? String, email)
        app.secureTextFields["sign-in.password"].typeText(MockScenarioValues.password + "\n")
    }

    @discardableResult static func dismissStrongPassword(in app: XCUIApplication) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let owners = [app, springboard]
        guard let owner = owners.first(where: { $0.buttons["GenerateStrongPasswordButton"].exists }) else {
            return false
        }
        let close = owner.buttons["xmark"]
        guard close.waitUntil(.exists, timeout: 2), close.isHittable else {
            XCTFail("Strong-password sheet has no reachable close control")
            return false
        }
        close.tap()
        let dismissed = { () -> Bool in
            !owner.buttons["GenerateStrongPasswordButton"].exists
        }
        XCTAssertTrue(UIWait.until(timeout: 3, condition: dismissed), "Expected the strong-password sheet to close")
        return true
    }

    @discardableResult static func type(
        _ text: String, into field: XCUIElement, in app: XCUIApplication, newPassword: Bool = false
    ) -> Bool {
        for _ in 0..<3 {
            dismissStrongPassword(in: app)
            reveal(field, in: app)
            field.tap()
            if newPassword, dismissStrongPassword(in: app) { continue }
            let focused = { () -> Bool in
                field.value(forKey: "hasKeyboardFocus") as? Bool == true
            }
            guard UIWait.until(timeout: 2, condition: focused) else { continue }
            if dismissStrongPassword(in: app) { continue }
            field.typeText(text)
            return true
        }
        XCTFail("Could not focus \(field.identifier) after declining strong-password AutoFill")
        return false
    }

    static func dismissKeyboard(in app: XCUIApplication, scrollIdentifier: String) {
        dismissStrongPassword(in: app)
        let scroll = scroll(in: app, identifier: scrollIdentifier)
        let window = app.windows.firstMatch
        for _ in 0..<2 {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists, SoftwareKeyboardVisibility.isVisible(keyboard.frame, in: window.frame) else {
                return
            }
            let visible = viewport(in: app, scrollFrame: scroll.frame)
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(dx: visible.midX - window.frame.minX, dy: visible.midY - window.frame.minY))
            let end = origin.withOffset(CGVector(dx: visible.midX - window.frame.minX, dy: window.frame.height - 1))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let hidden = { () -> Bool in
            !app.keyboards.firstMatch.exists
                || !SoftwareKeyboardVisibility.isVisible(app.keyboards.firstMatch.frame, in: window.frame)
        }
        XCTAssertTrue(UIWait.until(timeout: 3, condition: hidden), "Expected the software keyboard to dismiss")
    }

    static func scroll(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.scrollViews[identifier].firstMatch
    }

    private static func scroll(containing element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for containers in [app.scrollViews, app.collectionViews, app.tables] {
            let container = containers.containing(element.elementType, identifier: element.identifier).firstMatch
            if container.exists { return container }
        }
        return app.scrollViews.firstMatch
    }

    static func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        query(identifier, in: app).firstMatch
    }

    static func query(_ identifier: String, in scope: XCUIElement) -> XCUIElementQuery {
        if [
            "auth.brand", "auth.heading", "auth.subtitle", "auth.banner", "forgot.notice", "sign-up.consent",
            "verify.countdown", "verify.sign-out-error",
        ].contains(identifier) {
            return scope.staticTexts.matching(identifier: identifier)
        }
        if identifier.hasSuffix(".visibility") { return scope.switches.matching(identifier: identifier) }
        if identifier.hasSuffix(".password") || identifier.hasSuffix(".confirmation") {
            let secure = scope.secureTextFields.matching(identifier: identifier)
            return secure.firstMatch.exists ? secure : scope.textFields.matching(identifier: identifier)
        }
        if [".name", ".email", ".code", ".recovery_code"].contains(where: identifier.hasSuffix) {
            return scope.textFields.matching(identifier: identifier)
        }
        return scope.buttons.matching(identifier: identifier)
    }

    static func viewport(
        in app: XCUIApplication, scrollFrame: CGRect, includingNavigationBar: Bool = false
    ) -> CGRect {
        guard
            let viewport = viewportIfAvailable(
                in: app, scrollFrame: scrollFrame, includingNavigationBar: includingNavigationBar)
        else {
            XCTFail("Missing window safe-area diagnostic")
            return .zero
        }
        return viewport
    }

    static func viewportIfAvailable(
        in app: XCUIApplication, scrollFrame: CGRect, includingNavigationBar: Bool = false
    ) -> CGRect? {
        let window = app.windows.firstMatch
        guard window.exists, let value = window.value as? String, let data = value.data(using: .utf8),
            let values = try? JSONDecoder().decode([CGFloat].self, from: data), values.count == 4
        else {
            return nil
        }
        let safeArea = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            .offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        let keyboard = app.keyboards.firstMatch
        let viewport = AuthScrollGesture.viewport(
            window: window.frame, safeArea: safeArea, scroll: scrollFrame,
            keyboard: keyboard.exists ? keyboard.frame : nil, includingNavigationBar: includingNavigationBar)
        let navigation = app.navigationBars.firstMatch
        let tabs = app.tabBars.firstMatch
        return AuthScrollGesture.readingViewport(
            viewport, navigationBar: !includingNavigationBar && navigation.exists ? navigation.frame : nil,
            tabBar: tabs.exists ? tabs.frame : nil, clearance: 0)
    }

    static func assertBannerVisible(
        in app: XCUIApplication, scrollIdentifier: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let banner = app.staticTexts["auth.banner"].firstMatch
        guard banner.waitUntil(.exists, timeout: 5) else {
            XCTFail("Expected auth.banner", file: file, line: line)
            return
        }
        let scroll = scroll(in: app, identifier: scrollIdentifier)
        var stability = FrameStability()
        XCTAssertTrue(
            UIWait.until(timeout: 5) {
                let viewport = viewport(in: app, scrollFrame: scroll.frame)
                let keyboard = app.keyboards.firstMatch
                let visible =
                    banner.isHittable && AuthScrollGesture.fullyVisible(banner.frame, in: viewport)
                    && !SoftwareKeyboardVisibility.isVisible(
                        keyboard.exists ? keyboard.frame : .zero, in: app.windows.firstMatch.frame)
                return stability.observe(visible ? [banner.frame, viewport] : nil)
            }, "Banner must be fully visible with the keyboard dismissed", file: file, line: line)
    }

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil) {
        if element.isHittable { return }
        let scroll = scroll ?? self.scroll(containing: element, in: app)
        for _ in 0..<12 {
            do {
                if app.keyboards.firstMatch.exists
                    && SoftwareKeyboardVisibility.isVisible(
                        app.keyboards.firstMatch.frame, in: app.windows.firstMatch.frame)
                {
                    _ = try UIWait.keyboardFrames(in: app, including: [scroll, element])
                }
            } catch {
                XCTFail("Reveal frames did not settle for \(element.identifier): \(error)")
                return
            }
            let viewport = viewport(
                in: app, scrollFrame: scroll.frame, includingNavigationBar: element.identifier == "auth.back")
            if element.isHittable && AuthScrollGesture.fullyVisible(element.frame, in: viewport) { return }
            guard let gesture = AuthScrollGesture.reveal(element.frame, in: viewport) else { break }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            let window = app.windows.firstMatch.frame
            let start = origin.withOffset(
                CGVector(dx: gesture.start.x - window.minX, dy: gesture.start.y - window.minY))
            let end = origin.withOffset(CGVector(dx: gesture.end.x - window.minX, dy: gesture.end.y - window.minY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let viewport = viewport(
            in: app, scrollFrame: scroll.frame, includingNavigationBar: element.identifier == "auth.back")
        let message = "\(element.identifier): frame=\(element.frame), viewport=\(viewport)"
        XCTAssertTrue(element.isHittable, message)
        XCTAssertTrue(
            AuthScrollGesture.fullyVisible(element.frame, in: viewport), message)
    }
}

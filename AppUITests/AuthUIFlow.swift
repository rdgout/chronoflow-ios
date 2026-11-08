import XCTest

@MainActor enum AuthUIFlow {
    static func arguments(language: String = "en", xxLarge: Bool = false) -> [String] {
        var result = [
            "-cf.reduceMotion", "-AppleLanguages", "(\(language))", "-AppleLocale",
            language == "nl" ? "nl_NL" : "en_US",
        ]
        if xxLarge { result += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"] }
        return result
    }

    static func openSignIn(_ app: XCUIApplication) {
        let button = app.buttons["welcome.signIn"]
        XCTAssertTrue(button.waitForExistence(timeout: 12))
        reveal(button, in: app, scroll: app.scrollViews.containing(.button, identifier: "welcome.signIn").element)
        button.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    static func signIn(_ app: XCUIApplication, email: String) {
        let field = app.textFields["sign-in.email"]
        reveal(field, in: app)
        field.tap()
        field.typeText(email + "\n")
        app.secureTextFields["sign-in.password"].typeText(MockScenarioValues.password + "\n")
    }

    static func scroll(in app: XCUIApplication) -> XCUIElement {
        for screen in ["reset.scroll", "sign-up.scroll"] {
            if app.scrollViews[screen].exists { return app.scrollViews[screen] }
        }
        let forgot = app.scrollViews["forgot.scroll"]
        if forgot.exists { return forgot }
        let twoFactor = app.scrollViews["two-factor.scroll"]
        return twoFactor.exists ? twoFactor : app.scrollViews["sign-in.scroll"]
    }

    static func control(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        scroll(in: app).descendants(matching: .any).matching(identifier: identifier).element
    }

    static func viewport(
        in app: XCUIApplication, scrollFrame: CGRect, includingNavigationBar: Bool = false
    ) -> CGRect {
        let window = app.windows.firstMatch
        guard let value = window.value as? String, let data = value.data(using: .utf8),
            let values = try? JSONDecoder().decode([CGFloat].self, from: data), values.count == 4
        else {
            XCTFail("Missing window safe-area diagnostic")
            return .zero
        }
        let safeArea = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            .offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        let keyboard = app.keyboards.firstMatch
        return AuthScrollGesture.viewport(
            window: window.frame, safeArea: safeArea, scroll: scrollFrame,
            keyboard: keyboard.exists ? keyboard.frame : nil, includingNavigationBar: includingNavigationBar)
    }

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil) {
        let scroll =
            scroll
            ?? (element.identifier.hasPrefix("sign-in.")
                ? app.scrollViews["sign-in.scroll"]
                : element.identifier.hasPrefix("two-factor.")
                    ? app.scrollViews["two-factor.scroll"]
                    : element.identifier.hasPrefix("forgot.") ? app.scrollViews["forgot.scroll"] : self.scroll(in: app))
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
            if element.isHittable && viewport.contains(element.frame) { return }
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
            viewport.contains(element.frame), message)
    }
}

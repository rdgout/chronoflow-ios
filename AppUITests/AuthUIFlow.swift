import XCTest

@MainActor enum AuthUIFlow {
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
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 6), .completed, "Expected enabled \(element.identifier)")
    }

    static func openSignIn(_ app: XCUIApplication) {
        let button = app.buttons["welcome.signIn"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                button.exists || app.textFields["sign-in.email"].exists
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed)
        if app.textFields["sign-in.email"].exists { return }
        reveal(button, in: app, scroll: app.scrollViews.containing(.button, identifier: "welcome.signIn").element)
        button.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitForExistence(timeout: 4), "Expected sign-in.email after Welcome Sign in"
        )
        XCTAssertFalse(app.images["launch.opening"].exists)
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

    @discardableResult static func dismissStrongPassword(in app: XCUIApplication, wait: Bool = false) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let owners = [app, springboard]
        let presented = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                owners.contains { $0.buttons["GenerateStrongPasswordButton"].exists }
            }, object: nil)
        if wait { _ = XCTWaiter.wait(for: [presented], timeout: 1) }
        guard let owner = owners.first(where: { $0.buttons["GenerateStrongPasswordButton"].exists }) else {
            return false
        }
        let close = owner.buttons["xmark"]
        guard close.waitForExistence(timeout: 2), close.isHittable else {
            XCTFail("Strong-password sheet has no reachable close control")
            return false
        }
        close.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !owner.buttons["GenerateStrongPasswordButton"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        return true
    }

    @discardableResult static func type(
        _ text: String, into field: XCUIElement, in app: XCUIApplication, newPassword: Bool = false
    ) -> Bool {
        for _ in 0..<3 {
            dismissStrongPassword(in: app)
            reveal(field, in: app)
            field.tap()
            if newPassword, dismissStrongPassword(in: app, wait: true) { continue }
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in field.value(forKey: "hasKeyboardFocus") as? Bool == true },
                object: nil)
            guard XCTWaiter.wait(for: [focused], timeout: 2) == .completed else { continue }
            if dismissStrongPassword(in: app) { continue }
            field.typeText(text)
            return true
        }
        XCTFail("Could not focus \(field.identifier) after declining strong-password AutoFill")
        return false
    }

    static func dismissKeyboard(in app: XCUIApplication) {
        dismissStrongPassword(in: app)
        let scroll = scroll(in: app)
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
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !app.keyboards.firstMatch.exists
                    || !SoftwareKeyboardVisibility.isVisible(app.keyboards.firstMatch.frame, in: window.frame)
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    static func scroll(in app: XCUIApplication) -> XCUIElement {
        for screen in ["reset.scroll", "sign-up.scroll", "verify.scroll"] {
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

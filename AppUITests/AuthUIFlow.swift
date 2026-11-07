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
        reveal(button, in: app, scroll: app.scrollViews.firstMatch)
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

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil) {
        let scroll = scroll ?? app.scrollViews["auth.scroll"]
        for _ in 0..<12 {
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            if element.isHittable && viewport.contains(element.frame) { return }
            if element.frame.minY < viewport.minY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, element.identifier)
        XCTAssertTrue(
            scroll.frame.intersection(app.windows.firstMatch.frame).contains(element.frame), element.identifier)
    }
}

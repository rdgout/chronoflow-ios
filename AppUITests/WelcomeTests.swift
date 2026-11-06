import XCTest

nonisolated final class WelcomeTests: XCTestCase {
    @MainActor
    func testDutchAX5TextCanScrollToBothActions() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(nl)", "-AppleLocale", "nl_NL",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
        XCTAssertEqual(
            app.staticTexts["welcome.headline"].label,
            "Plan de verschuiving van je biologische klok voor je volgende reis")
        Self.scrollTo(app.buttons["welcome.signIn"], in: app)
        for (identifier, label) in [("welcome.plan", "Plan mijn reis"), ("welcome.signIn", "Inloggen")] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(WelcomeAuditPolicy.isFullyVisible(button.frame, in: app.windows.firstMatch.frame))
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 52)
        }
    }

    @MainActor
    fileprivate static func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable && WelcomeAuditPolicy.isFullyVisible(element.frame, in: app.windows.firstMatch.frame)
            {
                break
            }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(
            WelcomeAuditPolicy.isFullyVisible(element.frame, in: app.windows.firstMatch.frame),
            "\(element.identifier) frame \(element.frame) must be fully inside \(app.windows.firstMatch.frame)")
    }

    @MainActor
    fileprivate static func assertAccessibility(language: String, testCase: XCTestCase) async throws {
        let app = XCUIApplication()
        testCase.addTeardownBlock { @MainActor in app.terminate() }
        for appearance in [language == "nl" ? "Dark" : "Light"] {
            app.terminate()
            app.launchArguments = [
                "-cf.session", "out", "-cf.reduceMotion", "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "nl" ? "nl_NL" : "en_US",
                "-AppleInterfaceStyle", appearance,
            ]
            app.launch()
            XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
            _ = try UIWait.stableFrames(
                ["welcome.wordmark", "welcome.eyebrow", "welcome.headline"].map { app.staticTexts[$0] })
            try auditTopAndActions(app, language: language, appearance: appearance, testCase: testCase)
        }
    }

    @MainActor
    private static func auditTopAndActions(
        _ app: XCUIApplication, language: String, appearance: String, testCase: XCTestCase,
        types: XCUIAccessibilityAuditType = WelcomeAuditPolicy.welcomeAuditTypes
    ) throws {
        try audit(app, language: language, appearance: appearance, testCase: testCase, types: types)
        Self.scrollTo(app.buttons["welcome.signIn"], in: app)
        for identifier in ["welcome.plan", "welcome.signIn"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(
                WelcomeAuditPolicy.isFullyVisible(button.frame, in: app.windows.firstMatch.frame),
                "\(identifier) frame \(button.frame) must be fully inside \(app.windows.firstMatch.frame) for the audit"
            )
        }
        try audit(app, language: language, appearance: appearance, testCase: testCase, types: types)
    }

    @MainActor
    private static func audit(
        _ app: XCUIApplication, language: String, appearance: String, testCase: XCTestCase,
        types: XCUIAccessibilityAuditType = WelcomeAuditPolicy.welcomeAuditTypes
    ) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            let identifier = element?.identifier
            let label = element?.label
            let frame = element?.frame
            let window = app.windows.firstMatch.frame
            let boardContrast = WelcomeAuditPolicy.isBoardContrast(identifier: identifier, auditType: issue.auditType)
            let partiallyVisible = frame.map { !WelcomeAuditPolicy.isFullyVisible($0, in: window) } ?? false
            let ignored = WelcomeAuditPolicy.shouldIgnoreAuditIssue(
                identifier: identifier, auditType: issue.auditType, elementFrame: frame, window: window)
            let message = """
                Welcome accessibility [\(language), \(appearance)] \
                auditType=\(issue.auditType) identifier=\(identifier ?? "<nil>") \
                label=\(label ?? "<nil>") compactDescription=\(issue.compactDescription) \
                boardContrast=\(boardContrast) partiallyVisible=\(partiallyVisible) ignored=\(ignored)
                """
            print(message)
            let attachment = XCTAttachment(string: message)
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
            return ignored
        }
    }

}

nonisolated final class WelcomeEnglishAccessibilityTests: XCTestCase {
    @MainActor
    func testEnglishWelcomeAccessibility() async throws {
        try await WelcomeTests.assertAccessibility(language: "en", testCase: self)
    }
}

nonisolated final class WelcomeDutchAccessibilityTests: XCTestCase {
    @MainActor
    func testDutchWelcomeAccessibility() async throws {
        try await WelcomeTests.assertAccessibility(language: "nl", testCase: self)
    }
}

nonisolated final class WelcomeLogicTests: XCTestCase {
    @MainActor
    func testPlanMyTripOpensTheGuestWizard() {
        assertRoute(button: "welcome.plan", route: "guestWizard")
    }

    @MainActor
    func testSignInOpensSignIn() {
        assertRoute(button: "welcome.signIn", route: "signIn")
    }

    @MainActor
    private func assertRoute(button identifier: String, route: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.session", "out", "-cf.reduceMotion"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitForExistence(timeout: 6))
        let button = app.buttons[identifier]
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.staticTexts["route.\(route)"].waitForExistence(timeout: 3))
    }

}

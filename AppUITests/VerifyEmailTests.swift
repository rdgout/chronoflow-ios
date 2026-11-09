import XCTest

nonisolated final class VerifyEmailTests: ScreenTestCase {
    @MainActor func testPrefilledSignUpMailOpensWalkthrough() {
        let app = launchPrefilledSignUpApp()
        submitSignUp(app)
        let mail = app.buttons["verify.open-email"]
        XCTAssertTrue(
            mail.waitUntil(.exists, timeout: 8), "Expected verify.open-email after registering new@example.com")
        AuthUIFlow.waitUntilEnabled(mail)
        AuthUIFlow.reveal(mail, in: app)
        mail.tap()
        XCTAssertTrue(
            app.staticTexts["walkthrough.title"].waitUntil(.exists, timeout: 8),
            "Expected Walkthrough after mock-mail verification; registration already accepted the current terms")
    }
}

@MainActor func tamperedVerificationURL() -> String {
    "https://app.chronoflow.net/email/verify/\(MockScenarioValues.demoID)/\(String(repeating: "0", count: 40))?expires=4102444800&signature=\(String(repeating: "0", count: 64))"
}

@MainActor func launchPrefilledSignUpApp() -> XCUIApplication {
    let app = ScreenTestApp.makeApplication()
    app.launchArguments = AuthUIFlow.arguments()
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] = "sign-up"
    app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] = "verify"
    app.launchMeasured()
    openSignUp(app)
    return app
}

@MainActor func submitSignUp(_ app: XCUIApplication) {
    let button = app.buttons["sign-up.submit"]
    AuthUIFlow.reveal(button, in: app)
    button.tap()
}

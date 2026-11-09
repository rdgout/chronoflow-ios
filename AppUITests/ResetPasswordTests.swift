import XCTest

nonisolated final class ResetPasswordTests: ScreenTestCase {
    @MainActor func testMockInboxResetDoneAndSignInWithNewPassword() {
        let app = launchForgotApp()
        openResetFromMockMail(app)
        fillReset(app, password: "NewPassword123!", confirmation: "NewPassword123!")
        XCTAssertTrue(app.buttons["reset.continue"].waitUntil(.exists, timeout: 6))
        AuthUIFlow.reveal(app.buttons["reset.continue"], in: app)
        app.buttons["reset.continue"].tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 4))
        AuthUIFlow.reveal(app.textFields["sign-in.email"], in: app)
        app.textFields["sign-in.email"].tap()
        app.textFields["sign-in.email"].typeText(MockScenarioValues.demoEmail + "\n")
        app.secureTextFields["sign-in.password"].typeText("NewPassword123!\n")
        XCTAssertTrue(app.staticTexts["walkthrough.title"].waitUntil(.exists, timeout: 8))
    }
}

@MainActor func openResetFromMockMail(_ app: XCUIApplication) {
    if app.launchEnvironment["CF_UI_TEST_PROFILE"] == "screen",
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] == "reset",
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] != "expired"
    {
        XCTAssertTrue(app.secureTextFields["reset.password"].waitUntil(.exists, timeout: 6))
        return
    }
    openForgot(app)
    app.textFields["forgot.email"].tap()
    app.textFields["forgot.email"].typeText(MockScenarioValues.demoEmail + "\n")
    let mail = app.buttons["forgot.open-email"]
    XCTAssertTrue(mail.waitUntil(.exists, timeout: 6))
    AuthUIFlow.reveal(mail, in: app)
    mail.tap()
    XCTAssertTrue(app.secureTextFields["reset.password"].waitUntil(.exists, timeout: 6))
}

@MainActor func fillReset(_ app: XCUIApplication, password: String, confirmation: String) {
    let field = app.secureTextFields["reset.password"]
    guard AuthUIFlow.type(password + "\n", into: field, in: app, newPassword: true) else { return }
    let confirm = app.secureTextFields["reset.confirmation"]
    AuthUIFlow.type(confirmation + "\n", into: confirm, in: app, newPassword: true)
}

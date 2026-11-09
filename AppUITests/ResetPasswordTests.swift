import XCTest

nonisolated final class ResetPasswordTests: XCTestCase {
    @MainActor func testMockInboxResetDoneAndSignInWithNewPassword() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openResetFromMockMail(app)
        fillReset(app, password: "NewPassword123!", confirmation: "NewPassword123!")
        XCTAssertTrue(app.buttons["reset.continue"].waitForExistence(timeout: 6))
        AuthUIFlow.reveal(app.buttons["reset.continue"], in: app)
        app.buttons["reset.continue"].tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 4))
        AuthUIFlow.reveal(app.textFields["sign-in.email"], in: app)
        app.textFields["sign-in.email"].tap()
        app.textFields["sign-in.email"].typeText(MockScenarioValues.demoEmail + "\n")
        app.secureTextFields["sign-in.password"].typeText("NewPassword123!\n")
        XCTAssertTrue(app.staticTexts["route.walkthrough"].waitForExistence(timeout: 8))
    }
}

@MainActor func openResetFromMockMail(_ app: XCUIApplication) {
    openForgot(app)
    app.textFields["forgot.email"].tap()
    app.textFields["forgot.email"].typeText(MockScenarioValues.demoEmail + "\n")
    let mail = app.buttons["forgot.open-email"]
    XCTAssertTrue(mail.waitForExistence(timeout: 6))
    AuthUIFlow.reveal(mail, in: app)
    mail.tap()
    XCTAssertTrue(app.secureTextFields["reset.password"].waitForExistence(timeout: 6))
}

@MainActor func fillReset(_ app: XCUIApplication, password: String, confirmation: String) {
    let field = app.secureTextFields["reset.password"]
    AuthUIFlow.reveal(field, in: app)
    field.tap()
    field.typeText(password + "\n")
    let confirm = app.secureTextFields["reset.confirmation"]
    AuthUIFlow.reveal(confirm, in: app)
    confirm.tap()
    confirm.typeText(confirmation + "\n")
}

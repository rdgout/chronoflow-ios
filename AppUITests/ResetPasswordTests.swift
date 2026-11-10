import XCTest

nonisolated final class ResetPasswordTests: ScreenTestCase {
    @MainActor func testMockInboxResetDoneAndSignInWithNewPassword() {
        let app = AuthUIFlow.launchScreen("reset")
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
    AuthUIFlow.requireSeededScreen("reset", in: app)
}

@MainActor func fillReset(_ app: XCUIApplication, password: String, confirmation: String) {
    let field = app.secureTextFields["reset.password"]
    guard AuthUIFlow.type(password + "\n", into: field, in: app, newPassword: true) else { return }
    let confirm = app.secureTextFields["reset.confirmation"]
    AuthUIFlow.type(confirmation + "\n", into: confirm, in: app, newPassword: true)
}

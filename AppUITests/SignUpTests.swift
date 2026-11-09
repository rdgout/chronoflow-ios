import XCTest

nonisolated final class SignUpTests: XCTestCase {
    @MainActor func testRegistrationToggleConsentAndUnverifiedGate() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openSignUp(app)
        fillSignUp(app, email: "new@example.com", submit: false)
        let toggle = app.switches["sign-up.visibility"]
        AuthUIFlow.reveal(toggle, in: app)
        toggle.tap()
        XCTAssertTrue(app.textFields["sign-up.password"].exists && app.textFields["sign-up.confirmation"].exists)
        toggle.tap()
        let consent = AuthUIFlow.control("sign-up.consent", in: app)
        AuthUIFlow.reveal(consent, in: app)
        XCTAssertTrue(consent.exists)
        let submit = app.buttons["sign-up.submit"]
        AuthUIFlow.reveal(submit, in: app)
        submit.tap()
        XCTAssertTrue(app.staticTexts["route.verify"].waitForExistence(timeout: 8))
    }
}

@MainActor func openSignUp(_ app: XCUIApplication) {
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.reveal(app.buttons["sign-in.signup"], in: app)
    app.buttons["sign-in.signup"].tap()
    XCTAssertTrue(app.textFields["sign-up.name"].waitForExistence(timeout: 4))
}

@MainActor func fillSignUp(
    _ app: XCUIApplication, email: String, password: String = "NewPassword123!", confirmation: String? = nil,
    submit: Bool = true
) {
    for (identifier, value) in [
        ("sign-up.name", "Traveller"), ("sign-up.email", email), ("sign-up.password", password),
        ("sign-up.confirmation", confirmation ?? password),
    ] {
        let field =
            identifier.contains("password") || identifier.contains("confirmation")
            ? app.secureTextFields[identifier] : app.textFields[identifier]
        AuthUIFlow.reveal(field, in: app)
        field.tap()
        field.typeText(value + (identifier == "sign-up.confirmation" && !submit ? "" : "\n"))
    }
}

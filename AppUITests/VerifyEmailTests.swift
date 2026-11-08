import XCTest

nonisolated final class VerifyEmailTests: XCTestCase {
    @MainActor func testSignupMockMailVerificationPersistsAcrossRelaunch() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openSignUp(app)
        fillSignUp(app, email: "new@example.com")
        let mail = app.buttons["verify.open-email"]
        XCTAssertTrue(mail.waitForExistence(timeout: 8))
        AuthUIFlow.waitUntilEnabled(mail)
        AuthUIFlow.reveal(mail, in: app)
        mail.tap()
        XCTAssertTrue(app.staticTexts["route.terms"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["route.terms"].waitForExistence(timeout: 12))
    }
}

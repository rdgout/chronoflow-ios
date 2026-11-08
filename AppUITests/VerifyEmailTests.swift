import XCTest

nonisolated final class VerifyEmailTests: XCTestCase {
    @MainActor func testSignupMockMailVerificationPersistsAcrossRelaunch() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openSignUp(app)
        fillSignUp(app, email: "new@example.com")
        let mail = app.buttons["verify.open-email"]
        XCTAssertTrue(mail.waitForExistence(timeout: 8), "Expected verify.open-email after registering new@example.com")
        AuthUIFlow.waitUntilEnabled(mail)
        AuthUIFlow.reveal(mail, in: app)
        mail.tap()
        XCTAssertTrue(
            app.staticTexts["route.walkthrough"].waitForExistence(timeout: 8),
            "Expected Walkthrough after mock-mail verification; registration already accepted the current terms")
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["route.walkthrough"].waitForExistence(timeout: 12),
            "Expected persisted verified session to restore Walkthrough after relaunch")
    }
}

@MainActor func tamperedVerificationURL() -> String {
    "https://app.chronoflow.net/email/verify/\(MockScenarioValues.demoID)/\(String(repeating: "0", count: 40))?expires=4102444800&signature=\(String(repeating: "0", count: 64))"
}

import XCTest

nonisolated final class AccountRecoveryTests: XCTestCase {
    @MainActor func testSecondAccountConsumesItsOwnMailAfterTheFirstAccountIsWiped() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openSignUp(app)
        fillSignUp(app, email: "first@example.com")
        let different = app.buttons["verify.different-email"]
        XCTAssertTrue(
            different.waitForExistence(timeout: 8), "Expected verify.different-email for the unverified account")
        AuthUIFlow.waitUntilEnabled(different)
        AuthUIFlow.reveal(different, in: app)
        different.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitForExistence(timeout: 8),
            "Expected sign-in.email after discarding and wiping the unverified account")
        openSignUp(app)
        fillSignUp(app, email: "second@example.com")
        let mail = app.buttons["verify.open-email"]
        XCTAssertTrue(mail.waitForExistence(timeout: 8), "Expected verify.open-email for second@example.com")
        XCTAssertTrue(
            AuthUIFlow.control("auth.subtitle", in: app).label.contains("second@example.com"),
            "Expected Verify subtitle to identify second@example.com after the first account was wiped")
        AuthUIFlow.waitUntilEnabled(mail)
        AuthUIFlow.reveal(mail, in: app)
        mail.tap()
        XCTAssertTrue(
            app.staticTexts["walkthrough.title"].waitForExistence(timeout: 8),
            "Expected second account’s mail to verify its session and open Walkthrough with accepted terms")
    }

    @MainActor func testUnverifiedBackDiscardsAccountAndRelaunchRequiresSignIn() {
        let app = launchForgotApp()
        defer { app.terminate() }
        openSignUp(app)
        fillSignUp(app, email: "discard@example.com")
        let different = app.buttons["verify.different-email"]
        XCTAssertTrue(
            different.waitForExistence(timeout: 8), "Expected verify.different-email for the unverified account")
        AuthUIFlow.waitUntilEnabled(different)
        AuthUIFlow.reveal(different, in: app)
        different.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitForExistence(timeout: 8),
            "Expected sign-in.email after discarding and wiping the unverified account")
        app.terminate()
        app.launch()
        AuthUIFlow.openSignIn(app)
        XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
    }
    @MainActor func testMalformedUnboundLinkIsIgnoredAcrossAuthentication() {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_LINK"] = "https://app.chronoflow.net/email/verify/invalid"
        app.launch()
        defer { app.terminate() }
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(
            app.buttons["verify.open-email"].waitForExistence(timeout: 8),
            "Expected Verify waiting after sign-in; the malformed unbound link must be ignored")
        XCTAssertFalse(app.buttons["verify.retry"].exists)
    }

    @MainActor func testTamperedAccountBoundLinkWaitsForAuthenticationAndShowsFailed() {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_LINK"] = tamperedVerificationURL()
        app.launch()
        defer { app.terminate() }
        AuthUIFlow.openSignIn(app)
        XCTAssertFalse(app.buttons["verify.retry"].exists)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(
            app.buttons["verify.retry"].waitForExistence(timeout: 8),
            "Expected verify.retry after authenticating the account bound to the tampered link")
    }
}

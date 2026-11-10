import XCTest

nonisolated final class AccountRecoveryTests: ScreenTestCase {
    @MainActor func testSecondAccountConsumesItsOwnMailAfterTheFirstAccountIsWiped() {
        let app = launchPrefilledSignUpApp()
        submitSignUp(app)
        let different = app.buttons["verify.different-email"]
        XCTAssertTrue(
            different.waitUntil(.exists, timeout: 8), "Expected verify.different-email for the unverified account"
        )
        AuthUIFlow.waitUntilEnabled(different)
        AuthUIFlow.reveal(different, in: app)
        different.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitUntil(.exists, timeout: 8),
            "Expected sign-in.email after discarding and wiping the unverified account")
        app.buttons["sign-in.signup"].tap()
        XCTAssertTrue(app.textFields["sign-up.name"].waitUntil(.exists, timeout: 4))
        let email = app.textFields["sign-up.email"]
        AuthUIFlow.reveal(email, in: app)
        email.tap()
        email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (email.value as? String ?? "").count))
        email.typeText("second@example.com\n")
        submitSignUp(app)
        let mail = app.buttons["verify.open-email"]
        XCTAssertTrue(mail.waitUntil(.exists, timeout: 8), "Expected verify.open-email for second@example.com")
        XCTAssertTrue(
            AuthUIFlow.control("auth.subtitle", in: app).label.contains("second@example.com"),
            "Expected Verify subtitle to identify second@example.com after the first account was wiped")
        AuthUIFlow.waitUntilEnabled(mail)
        AuthUIFlow.reveal(mail, in: app)
        mail.tap()
        XCTAssertTrue(
            app.staticTexts["walkthrough.title"].waitUntil(.exists, timeout: 8),
            "Expected second account’s mail to verify its session and open Walkthrough with accepted terms")
    }

    @MainActor func testUnverifiedDifferentEmailReturnsToSignIn() {
        let app = launchPrefilledSignUpApp()
        submitSignUp(app)
        let different = app.buttons["verify.different-email"]
        XCTAssertTrue(
            different.waitUntil(.exists, timeout: 8), "Expected verify.different-email for the unverified account"
        )
        AuthUIFlow.waitUntilEnabled(different)
        AuthUIFlow.reveal(different, in: app)
        different.tap()
        XCTAssertTrue(
            app.textFields["sign-in.email"].waitUntil(.exists, timeout: 8),
            "Expected sign-in.email after discarding and wiping the unverified account")
        XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
    }
    @MainActor func testTamperedLinkOpensFailedScreen() {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_LINK"] = tamperedVerificationURL()
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: true)
        XCTAssertTrue(
            app.buttons["verify.retry"].waitUntil(.exists, timeout: 12),
            "Expected verify.retry after authenticating the account bound to the tampered link")
    }
}

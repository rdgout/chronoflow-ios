import XCTest

nonisolated final class AuthBannerVisibilityTests: ScreenTestCase {
    @MainActor func testTakenEmailBannerIsVisible() { checkSignUp(xxLarge: false, offline: false) }
    @MainActor func testTakenEmailBannerIsVisibleAtXXLarge() { checkSignUp(xxLarge: true, offline: false) }
    @MainActor func testOfflineSignUpBannerIsVisible() { checkSignUp(xxLarge: false, offline: true) }
    @MainActor func testOfflineSignUpBannerIsVisibleAtXXLarge() { checkSignUp(xxLarge: true, offline: true) }
    @MainActor func testCredentialsBannerIsVisible() { checkSignIn(xxLarge: false) }
    @MainActor func testCredentialsBannerIsVisibleAtXXLarge() { checkSignIn(xxLarge: true) }
    @MainActor func testForgotBannerIsVisible() { checkForgot(xxLarge: false) }
    @MainActor func testForgotBannerIsVisibleAtXXLarge() { checkForgot(xxLarge: true) }
    @MainActor func testResetBannerIsVisible() { checkReset(xxLarge: false) }
    @MainActor func testResetBannerIsVisibleAtXXLarge() { checkReset(xxLarge: true) }
    @MainActor func testTwoFactorBannerIsVisible() throws { try checkTwoFactor(xxLarge: false) }
    @MainActor func testTwoFactorBannerIsVisibleAtXXLarge() throws { try checkTwoFactor(xxLarge: true) }
    @MainActor func testVerifyBannerIsVisible() { checkVerify(xxLarge: false) }
    @MainActor func testVerifyBannerIsVisibleAtXXLarge() { checkVerify(xxLarge: true) }

    @MainActor private func checkSignUp(xxLarge: Bool, offline: Bool) {
        let app = AuthUIFlow.launchScreen(
            "sign-up", state: nil, xxLarge: xxLarge, extraEnv: offline ? ["CF_AUTH_TEST_OFFLINE": "1"] : [:])
        openSignUp(app)
        fillSignUp(app, email: offline ? "new@example.com" : MockScenarioValues.demoEmail)
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "sign-up.scroll")
        let banner = AuthUIFlow.control("auth.banner", in: app)
        XCTAssertTrue(
            banner.label.contains(offline ? "Needs a connection" : "There's already an account with this email."))
        XCTAssertTrue(app.buttons["sign-up.submit"].isEnabled)
        if !offline {
            let signIn = app.buttons["sign-up.back"]
            AuthUIFlow.reveal(signIn, in: app)
            signIn.tap()
            XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 4))
        }
    }

    @MainActor private func checkSignIn(xxLarge: Bool) {
        let app = AuthUIFlow.launchScreen("sign-in", state: nil, xxLarge: xxLarge)
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: "unknown@example.com")
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "sign-in.scroll")
        XCTAssertTrue(AuthUIFlow.control("auth.banner", in: app).label.contains("That email and password don't match."))
    }

    @MainActor private func checkForgot(xxLarge: Bool) {
        let app = launchForgotApp(xxLarge: xxLarge, failure: "server")
        openForgot(app)
        let email = app.textFields["forgot.email"]
        email.tap()
        email.typeText("retained@example.com\n")
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "forgot.scroll")
    }

    @MainActor private func checkReset(xxLarge: Bool) {
        let app = AuthUIFlow.launchScreen(
            "reset", state: nil, xxLarge: xxLarge, extraEnv: ["CF_AUTH_TEST_RESET_FAILURE": "server"])
        openResetFromMockMail(app)
        fillReset(app, password: "NewPassword123!", confirmation: "NewPassword123!")
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "reset.scroll")
    }

    @MainActor private func checkTwoFactor(xxLarge: Bool) throws {
        let app = launchTwoFactorApp(xxLarge: xxLarge, server: true)
        try openMockTwoFactor(app)
        let code = app.textFields["two-factor.code"]
        code.tap()
        code.typeText("123456")
        AuthUIFlow.reveal(app.buttons["two-factor.submit"], in: app)
        app.buttons["two-factor.submit"].tap()
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "two-factor.scroll")
    }

    @MainActor private func checkVerify(xxLarge: Bool) {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments(xxLarge: xxLarge)
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true,
            extraEnv: ["CF_AUTH_TEST_UNVERIFIED": "1", "CF_AUTH_TEST_VERIFY_STATE": "server"])
        let resend = app.buttons["verify.resend"]
        XCTAssertTrue(resend.waitForExistence(timeout: 8))
        AuthUIFlow.waitUntilEnabled(resend)
        AuthUIFlow.reveal(resend, in: app)
        resend.tap()
        AuthUIFlow.assertBannerVisible(in: app, scrollIdentifier: "verify.scroll")
    }
}

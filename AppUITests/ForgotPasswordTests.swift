import XCTest

nonisolated final class ForgotPasswordTests: ScreenTestCase {
    @MainActor func testSentNoticeAndBackToSignIn() throws {
        let email = MockScenarioValues.demoEmail
        let app = launchForgotApp()
        openForgot(app)
        let field = AuthUIFlow.control("forgot.email", in: app)
        AuthUIFlow.reveal(field, in: app)
        field.tap()
        field.typeText(email + "\n")
        let notice = AuthUIFlow.control("forgot.notice", in: app)
        XCTAssertTrue(notice.waitUntil(.exists, timeout: 6))
        AuthUIFlow.reveal(notice, in: app)
        XCTAssertTrue(notice.label.contains("Check your inbox."))
        XCTAssertTrue(notice.label.contains("If \(email) has an account"))
        XCTAssertFalse(AuthUIFlow.control("forgot.email", in: app).exists)
        let mail = AuthUIFlow.control("forgot.open-email", in: app)
        AuthUIFlow.reveal(mail, in: app)
        XCTAssertTrue(mail.isHittable)
        let back = AuthUIFlow.control("forgot.back", in: app)
        AuthUIFlow.reveal(back, in: app)
        back.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 3))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testServerBannerClearsOnEdit() throws {
        let app = launchForgotApp(failure: "server")
        openForgot(app)
        let field = app.textFields["forgot.email"]
        guard AuthUIFlow.type("retained@example.com\n", into: field, in: app) else { return }
        let banner = AuthUIFlow.control("auth.banner", in: app)
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 6), "Expected Forgot server banner after submitting")
        XCTAssertTrue(
            banner.label.contains("Something went wrong on our side."), "Expected Forgot server failure copy")
        XCTAssertEqual(field.value as? String, "retained@example.com", "Expected the submitted email to be retained")
        XCTAssertTrue(field.waitUntil(.enabled, timeout: 6), "Expected Forgot email to unlock after the server failure")
        XCTAssertFalse(
            AuthUIFlow.control("forgot.notice", in: app).exists, "Server failure must not show a sent notice")
        AuthUIFlow.assertBannerVisible(in: app)
        guard AuthUIFlow.type("x", into: field, in: app) else { return }
        XCTAssertTrue(banner.waitUntil(.gone, timeout: 3), "Expected the server banner to clear after editing email")
    }

    @MainActor func testOfflineShowsConnectionBannerAndKeepsSubmitEnabled() throws {
        let app = launchForgotApp(offline: true)
        openForgot(app)
        let field = app.textFields["forgot.email"]
        field.tap()
        field.typeText("offline@example.com\n")
        AuthUIFlow.assertBannerVisible(in: app)
        XCTAssertEqual(field.value as? String, "offline@example.com")
        let banner = AuthUIFlow.control("auth.banner", in: app)
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 5))
        XCTAssertTrue(banner.label.contains("Needs a connection"))
        XCTAssertFalse(AuthUIFlow.control("forgot.notice", in: app).exists)
        XCTAssertTrue(AuthUIFlow.control("forgot.submit", in: app).isEnabled)
        AuthUIFlow.reveal(AuthUIFlow.control("auth.back", in: app), in: app)
        AuthUIFlow.control("auth.back", in: app).tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 3))
    }
}

@MainActor func launchForgotApp(
    language: String = "en", xxLarge: Bool = false, failure: String? = nil, offline: Bool = false,
    appearance: XCUIDevice.Appearance? = nil, seedScreen: Bool = false
) -> XCUIApplication {
    let app = ScreenTestApp.makeApplication()
    app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
    if let appearance { app.launchArguments += ["-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light"] }
    if seedScreen { app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] = "forgot" }
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    if offline { app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1" }
    if failure == "server" { app.launchArguments += ["-cf.forgotServerFailure"] }
    if failure == "throttle" { app.launchArguments += ["-cf.forgotThrottleFailure"] }
    app.launchMeasured()
    return app
}

@MainActor func openForgot(_ app: XCUIApplication) {
    if app.launchEnvironment["CF_UI_TEST_PROFILE"] == "screen",
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] == "forgot"
    {
        XCTAssertTrue(
            UIWait.until(timeout: 12) {
                app.textFields["forgot.email"].exists || app.textFields["sign-in.email"].exists
                    || app.buttons["welcome.signIn"].exists
            }, "Expected Forgot, Sign in or Welcome after Forgot seed readiness")
        if app.textFields["forgot.email"].exists { return }
    }
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.reveal(app.buttons["sign-in.forgot"], in: app)
    app.buttons["sign-in.forgot"].tap()
    XCTAssertTrue(
        app.textFields["forgot.email"].waitUntil(.exists, timeout: 4),
        "Expected Forgot email after tapping Forgot password on Sign in")
    AuthUIFlow.reveal(app.textFields["forgot.email"], in: app)
}

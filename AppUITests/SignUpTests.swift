import XCTest

nonisolated final class SignUpTests: XCTestCase {
    @MainActor func testOfflineRegistrationShowsConnectionBanner() {
        let app = submitPrefilledSignUp(state: "offline", offline: true)
        defer { app.terminate() }
        let banner = AuthUIFlow.control("auth.banner", in: app)
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 6))
        AuthUIFlow.reveal(banner, in: app)
        XCTAssertTrue(banner.isHittable)
        XCTAssertTrue(banner.label.contains("Needs a connection"))
        XCTAssertEqual(app.textFields["sign-up.name"].value as? String, "Traveller")
        XCTAssertEqual(app.textFields["sign-up.email"].value as? String, "new@example.com")
        XCTAssertTrue(app.buttons["sign-up.submit"].isEnabled)
        XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
    }

    @MainActor func testTakenEmailOffersTheDesignedSignInPath() {
        let app = submitPrefilledSignUp(state: "taken")
        defer { app.terminate() }
        let banner = AuthUIFlow.control("auth.banner", in: app)
        XCTAssertTrue(banner.waitUntil(.exists, timeout: 6))
        XCTAssertTrue(banner.label.contains("There's already an account with this email."))
        let signIn = app.buttons["sign-up.back"]
        AuthUIFlow.reveal(signIn, in: app)
        XCTAssertTrue(signIn.label.contains("Already have an account? Sign in"))
        signIn.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 4))
    }

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
        XCTAssertTrue(app.scrollViews["verify.scroll"].waitUntil(.exists, timeout: 8))
    }

    @MainActor private func submitPrefilledSignUp(state: String, offline: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_SCREEN"] = "sign-up"
        app.launchEnvironment["CF_AUTH_TEST_AUDIT_STATE"] = state
        if offline { app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1" }
        app.launchMeasured()
        openSignUp(app)
        let submit = app.buttons["sign-up.submit"]
        AuthUIFlow.reveal(submit, in: app)
        submit.tap()
        return app
    }
}

@MainActor func openSignUp(_ app: XCUIApplication) {
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.reveal(app.buttons["sign-in.signup"], in: app)
    app.buttons["sign-in.signup"].tap()
    XCTAssertTrue(
        app.textFields["sign-up.name"].waitUntil(.exists, timeout: 4),
        "Expected sign-up.name after opening Create account")
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
        guard
            AuthUIFlow.type(
                value + (identifier == "sign-up.confirmation" && !submit ? "" : "\n"), into: field, in: app,
                newPassword: identifier == "sign-up.password" || identifier == "sign-up.confirmation")
        else { return }
    }
}

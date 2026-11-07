import XCTest

nonisolated final class ForgotPasswordTests: XCTestCase {
    @MainActor func testExistingAndUnknownEmailsShowTheSameNoticeAndReturnToSignIn() throws {
        for email in [MockScenarioValues.demoEmail, "unknown@example.com"] {
            let app = launchForgotApp()
            defer { app.terminate() }
            openForgot(app)
            let field = AuthUIFlow.control("forgot.email", in: app)
            AuthUIFlow.reveal(field, in: app)
            field.tap()
            field.typeText(email + "\n")
            let notice = AuthUIFlow.control("forgot.notice", in: app)
            XCTAssertTrue(notice.waitForExistence(timeout: 6))
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
            XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.images["launch.opening"].exists)
            AuthUIFlow.reveal(app.buttons["sign-in.forgot"], in: app)
            app.buttons["sign-in.forgot"].tap()
            XCTAssertTrue(app.textFields["forgot.email"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.textFields["forgot.email"].value as? String, "")
            XCTAssertFalse(AuthUIFlow.control("forgot.notice", in: app).exists)
        }
    }

    @MainActor func testServerAndThrottlePreserveEmailAndClearOnEdit() throws {
        for failure in ["server", "throttle"] {
            let app = launchForgotApp(failure: failure)
            defer { app.terminate() }
            openForgot(app)
            let field = app.textFields["forgot.email"]
            field.tap()
            field.typeText("retained@example.com\n")
            let banner = AuthUIFlow.control("auth.banner", in: app)
            XCTAssertTrue(banner.waitForExistence(timeout: 6))
            XCTAssertTrue(
                banner.label.contains(failure == "server" ? "Something went wrong on our side." : "Too many requests."))
            XCTAssertEqual(field.value as? String, "retained@example.com")
            XCTAssertTrue(field.isEnabled)
            XCTAssertFalse(AuthUIFlow.control("forgot.notice", in: app).exists)
            field.typeText("x")
            XCTAssertFalse(banner.exists)
        }
    }

    @MainActor func testOfflineKeepsTheDesignedFormAndSubmitEnabled() throws {
        let app = launchForgotApp(offline: true)
        defer { app.terminate() }
        openForgot(app)
        let field = app.textFields["forgot.email"]
        field.tap()
        field.typeText("offline@example.com\n")
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in field.isEnabled && app.keyboards.firstMatch.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 5), .completed)
        XCTAssertEqual(field.value as? String, "offline@example.com")
        XCTAssertFalse(AuthUIFlow.control("auth.banner", in: app).exists)
        XCTAssertFalse(AuthUIFlow.control("forgot.notice", in: app).exists)
        XCTAssertTrue(AuthUIFlow.control("forgot.submit", in: app).isEnabled)
        AuthUIFlow.reveal(AuthUIFlow.control("auth.back", in: app), in: app)
        AuthUIFlow.control("auth.back", in: app).tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 3))
    }
}

@MainActor func launchForgotApp(
    language: String = "en", xxLarge: Bool = false, failure: String? = nil, offline: Bool = false
) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = AuthUIFlow.arguments(language: language, xxLarge: xxLarge)
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    if offline { app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1" }
    if failure == "server" { app.launchArguments += ["-cf.forgotServerFailure"] }
    if failure == "throttle" { app.launchArguments += ["-cf.forgotThrottleFailure"] }
    app.launch()
    return app
}

@MainActor func openForgot(_ app: XCUIApplication) {
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.reveal(app.buttons["sign-in.forgot"], in: app)
    app.buttons["sign-in.forgot"].tap()
    XCTAssertTrue(app.textFields["forgot.email"].waitForExistence(timeout: 4))
    AuthUIFlow.reveal(app.textFields["forgot.email"], in: app)
}

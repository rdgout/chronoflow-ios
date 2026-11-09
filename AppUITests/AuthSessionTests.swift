import XCTest

nonisolated final class AuthSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor func testVerifiedSignInRelaunchAndForegroundRestoreWithoutIntroReplay() throws {
        let app = launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        assertRoute("today", in: app)
        waitForCache(in: app)
        app.terminate()
        app.launch()
        assertRoute("today", in: app)
        XCTAssertFalse(app.buttons["welcome.signIn"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertRoute("today", in: app)
        signOut(app, route: "today")
    }

    @MainActor func testTwoFactorCodeAcceptsSessionOnlyAfterVerification() throws {
        try twoFactor(recovery: false)
    }

    @MainActor func testTwoFactorRecoveryAcceptsSessionAndSurvivesRelaunch() throws {
        try twoFactor(recovery: true)
    }

    @MainActor func testUnverifiedAccountUsesVerifyScreenOnSignInAndRestore() {
        let app = launch(unverified: true)
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        assertRoute("verify", in: app)
        XCTAssertFalse(app.staticTexts["route.walkthrough"].exists)
        XCTAssertFalse(app.staticTexts["route.today"].exists)
        app.terminate()
        app.launch()
        assertRoute("verify", in: app)
        signOut(app, route: "verify")
    }

    @MainActor func testOfflineCachedRestoreThenSignOutWipesTheRestorableSession() {
        let app = launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        assertRoute("today", in: app)
        waitForCache(in: app)
        app.terminate()
        app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1"
        app.launch()
        assertRoute("today", in: app)
        let offlineAttempt = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "cached:failed-offline"),
            object: app.staticTexts["route.today"])
        XCTAssertEqual(XCTWaiter.wait(for: [offlineAttempt], timeout: 12), .completed)
        signOut(app, route: "today")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["welcome.signIn"].waitForExistence(timeout: 12))
        AuthUIFlow.openSignIn(app)
        XCTAssertEqual(app.textFields["sign-in.email"].value as? String, "")
        XCTAssertEqual(app.secureTextFields["sign-in.password"].value as? String, "")
        XCTAssertFalse(app.staticTexts["route.today"].exists)
        XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
        XCTAssertFalse(app.textFields["two-factor.code"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor private func twoFactor(recovery: Bool) throws {
        let app = launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
        let code = app.textFields["two-factor.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["route.walkthrough"].exists)
        XCTAssertFalse(app.staticTexts["route.today"].exists)
        if recovery {
            AuthUIFlow.reveal(app.buttons["two-factor.toggle"], in: app)
            app.buttons["two-factor.toggle"].tap()
        }
        let field = app.textFields[recovery ? "two-factor.recovery_code" : "two-factor.code"]
        AuthUIFlow.reveal(field, in: app)
        field.tap()
        field.typeText(recovery ? MockScenarioValues.recoveryCode : MockScenarioValues.twoFactorCode)
        try assertTwoFactorKeyboardPair(field, app: app, attach: add)
        app.buttons["two-factor.submit"].tap()
        assertRoute("today", in: app)
        XCTAssertFalse(field.exists)
        waitForCache(in: app)
        app.terminate()
        app.launch()
        assertRoute("today", in: app)
        XCTAssertFalse(app.textFields["two-factor.code"].exists)
        signOut(app, route: "today")
    }

    @MainActor private func launch(unverified: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = unverified ? "1" : "0"
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    @MainActor private func assertRoute(_ route: String, in app: XCUIApplication) {
        if route == "verify" {
            XCTAssertTrue(app.scrollViews["verify.scroll"].waitForExistence(timeout: 12))
        } else {
            XCTAssertTrue(app.staticTexts["route.\(route)"].waitForExistence(timeout: 12))
        }
        XCTAssertFalse(app.images["launch.opening"].exists)
        XCTAssertFalse(app.staticTexts["welcome.wordmark"].exists)
    }

    @MainActor private func waitForCache(in app: XCUIApplication) {
        let cached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "cached:idle"),
            object: app.staticTexts["route.today"])
        XCTAssertEqual(XCTWaiter.wait(for: [cached], timeout: 12), .completed)
    }

    @MainActor private func signOut(_ app: XCUIApplication, route: String) {
        if route == "verify" {
            let different = app.buttons["verify.different-email"]
            AuthUIFlow.waitUntilEnabled(different)
            AuthUIFlow.reveal(different, in: app)
            different.tap()
        } else {
            app.staticTexts["route.\(route)"].tap()
        }
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 8))
        if route == "verify" {
            XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
        } else {
            XCTAssertFalse(app.staticTexts["route.\(route)"].exists)
        }
        XCTAssertFalse(app.images["launch.opening"].exists)
        XCTAssertFalse(app.staticTexts["welcome.wordmark"].exists)
    }
}

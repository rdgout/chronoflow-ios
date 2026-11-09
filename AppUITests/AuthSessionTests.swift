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
        app.launchMeasured(profile: .launch)
        assertRoute("today", in: app)
        XCTAssertFalse(app.buttons["welcome.signIn"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertRoute("today", in: app)
        signOut(app, route: "today")
    }

    @MainActor func testSeededUnverifiedAccountShowsVerify() {
        let app = XCUIApplication()
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true, extraEnv: ["CF_UI_TEST_PROFILE": "launch", "CF_AUTH_TEST_UNVERIFIED": "1"])
        defer { app.terminate() }
        assertRoute("verify", in: app)
        XCTAssertFalse(app.staticTexts["walkthrough.title"].exists)
        XCTAssertFalse(app.scrollViews["today.screen"].exists)
    }

    @MainActor func testSeededOfflineAccountShowsTodayAndSignOutReturnsToWelcomeOnRelaunch() {
        let app = XCUIApplication()
        AuthUIFlow.launchSignedIn(
            app, walkthroughSeen: true, extraEnv: ["CF_UI_TEST_PROFILE": "launch", "CF_AUTH_TEST_OFFLINE": "1"])
        defer { app.terminate() }
        assertRoute("today", in: app)
        XCTAssertTrue(app.buttons["today.trip"].waitUntil(.exists, timeout: 10))
        signOut(app, route: "today")
        app.terminate()
        app.launchMeasured(profile: .launch)
        XCTAssertTrue(app.buttons["welcome.signIn"].waitUntil(.exists, timeout: 12))
        XCTAssertFalse(app.scrollViews["today.screen"].exists)
    }

    @MainActor private func launch(unverified: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launchEnvironment["CF_AUTH_TEST_UNVERIFIED"] = unverified ? "1" : "0"
        app.launchMeasured(profile: .launch)
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    @MainActor private func assertRoute(_ route: String, in app: XCUIApplication) {
        if route == "verify" {
            XCTAssertTrue(app.scrollViews["verify.scroll"].waitUntil(.exists, timeout: 12))
        } else if route == "today" {
            XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 12))
        } else {
            XCTAssertTrue(app.staticTexts["route.\(route)"].waitUntil(.exists, timeout: 12))
        }
        XCTAssertFalse(app.images["launch.opening"].exists)
        XCTAssertFalse(app.staticTexts["welcome.wordmark"].exists)
    }

    @MainActor private func waitForCache(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["today.trip"].waitUntil(.exists, timeout: 12))
    }

    @MainActor private func signOut(_ app: XCUIApplication, route: String) {
        if route == "verify" {
            let different = app.buttons["verify.different-email"]
            AuthUIFlow.waitUntilEnabled(different)
            AuthUIFlow.reveal(different, in: app)
            different.tap()
        } else {
            app.tabBars.buttons["Settings"].tap()
            let button = app.buttons["settings.signOut"]
            XCTAssertTrue(button.waitUntil(.exists, timeout: 6))
            AuthUIFlow.reveal(button, in: app)
            button.tap()
        }
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 8))
        if route == "verify" {
            XCTAssertFalse(app.scrollViews["verify.scroll"].exists)
        } else {
            XCTAssertFalse(app.staticTexts["route.\(route)"].exists)
        }
        XCTAssertFalse(app.images["launch.opening"].exists)
        XCTAssertFalse(app.staticTexts["welcome.wordmark"].exists)
    }
}

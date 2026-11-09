import XCTest

nonisolated final class SettingsTests: ScreenTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testSignOutWithNoPendingOpensSignInWithoutReplayingLaunch() {
        let app = launch(pending: false)
        openSettings(app)
        signOut(app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 10))
        XCTAssertFalse(app.scrollViews["settings.pending"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testPendingSignOutStayAndDiscard() {
        let app = launch(pending: true)
        openSettings(app)
        let pending = { app.staticTexts["settings.sync"].label == "1 change waiting to sync" }
        XCTAssertTrue(UIWait.until(timeout: 12, condition: pending))
        signOut(app)
        let sheet = app.scrollViews["settings.pending"]
        guard sheet.waitUntil(.exists, timeout: 8) else {
            XCTFail("Pending changes confirmation did not appear")
            return
        }
        XCTAssertTrue(app.staticTexts["settings.pending.title"].label.contains("1 change"))
        let stay = app.buttons["settings.pending.stay"]
        AuthUIFlow.reveal(stay, in: app, scroll: sheet)
        stay.tap()
        let dismissed = { () -> Bool in
            !sheet.exists
        }
        XCTAssertTrue(UIWait.until(timeout: 4, condition: dismissed))
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitUntil(.exists, timeout: 4))
        XCTAssertFalse(app.textFields["sign-in.email"].exists)
        signOut(app)
        XCTAssertTrue(sheet.waitUntil(.exists, timeout: 8))
        let discard = app.buttons["settings.pending.discard"]
        AuthUIFlow.reveal(discard, in: app, scroll: sheet)
        discard.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitUntil(.exists, timeout: 10))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor private func launch(pending: Bool) -> XCUIApplication {
        let app = ScreenTestApp.makeApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        if pending { app.launchEnvironment["CF_SETTINGS_TEST_PENDING"] = "1" }
        AuthUIFlow.launchSignedIn(app, walkthroughSeen: true)
        return app
    }

    @MainActor private func openSettings(_ app: XCUIApplication, email: String = MockScenarioValues.demoEmail) {
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitUntil(.exists, timeout: 12))
        app.tabBars.buttons["Settings"].tap()
        let profile = app.buttons["settings.profile"].firstMatch
        XCTAssertTrue(profile.waitUntil(.exists, timeout: 10))
        XCTAssertTrue(profile.label.contains(email))
    }

    @MainActor private func signOut(_ app: XCUIApplication) {
        let screen = app.collectionViews["settings.screen"].firstMatch
        XCTAssertTrue(screen.waitUntil(.exists, timeout: 6))
        let button = app.buttons["settings.signOut"]
        AuthUIFlow.reveal(button, in: app, scroll: screen)
        AuthUIFlow.waitUntilEnabled(button)
        button.tap()
    }
}

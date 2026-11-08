import XCTest

nonisolated final class SettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testSignOutWithNoPendingOpensSignInWithoutReplayingLaunch() {
        let app = launch(pending: false)
        defer { app.terminate() }
        openSettings(app)
        signOut(app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.scrollViews["settings.pending"].exists)
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor func testPendingStayThenDiscardAndNextAccountHasNoOldQueue() {
        let app = launch(pending: true)
        defer { app.terminate() }
        openSettings(app)
        let pending = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1 change waiting to sync"),
            object: app.staticTexts["settings.sync"])
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 12), .completed)
        signOut(app)
        let sheet = app.scrollViews["settings.pending"]
        guard sheet.waitForExistence(timeout: 8) else {
            XCTFail("Pending changes confirmation did not appear")
            return
        }
        XCTAssertTrue(app.staticTexts["settings.pending.title"].label.contains("1 change"))
        let stay = app.buttons["settings.pending.stay"]
        AuthUIFlow.reveal(stay, in: app, scroll: sheet)
        stay.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !sheet.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 4), .completed)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.textFields["sign-in.email"].exists)
        signOut(app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let discard = app.buttons["settings.pending.discard"]
        AuthUIFlow.reveal(discard, in: app, scroll: sheet)
        discard.tap()
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["launch.opening"].exists)
        AuthUIFlow.signIn(app, email: MockScenarioValues.twoFactorEmail)
        let code = app.textFields["two-factor.code"]
        guard code.waitForExistence(timeout: 6) else {
            XCTFail("The seeded second account did not reach two-factor verification")
            return
        }
        AuthUIFlow.reveal(code, in: app)
        code.tap()
        code.typeText(MockScenarioValues.twoFactorCode)
        let verify = app.buttons["two-factor.submit"]
        AuthUIFlow.reveal(verify, in: app)
        AuthUIFlow.waitUntilEnabled(verify)
        verify.tap()
        XCTAssertTrue(
            app.scrollViews["today.screen"].waitForExistence(timeout: 12),
            "Both seeded accounts must bypass Walkthrough with CF_AUTH_TEST_WALKTHROUGH_SEEN")
        XCTAssertFalse(app.buttons["walkthrough.skip"].exists)
        openSettings(app, email: MockScenarioValues.twoFactorEmail)
        signOut(app)
        XCTAssertTrue(app.textFields["sign-in.email"].waitForExistence(timeout: 10))
        XCTAssertFalse(sheet.exists)
    }

    @MainActor private func launch(pending: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        if pending { app.launchEnvironment["CF_SETTINGS_TEST_PENDING"] = "1" }
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        return app
    }

    @MainActor private func openSettings(_ app: XCUIApplication, email: String = MockScenarioValues.demoEmail) {
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 12))
        app.tabBars.buttons["Settings"].tap()
        let profile = app.buttons["settings.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertTrue(profile.label.contains(email))
    }

    @MainActor private func signOut(_ app: XCUIApplication) {
        let screen = app.descendants(matching: .any)["settings.screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 6))
        let button = app.buttons["settings.signOut"]
        AuthUIFlow.reveal(button, in: app, scroll: screen)
        AuthUIFlow.waitUntilEnabled(button)
        button.tap()
    }
}

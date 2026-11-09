import XCTest

nonisolated final class RemindersTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testTogglePersistsAcrossRelaunch() {
        let app = launch(permission: "granted")
        defer { app.terminate() }
        openReminders(app)
        let toggle = app.switches["reminders.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        AuthUIFlow.waitUntilEnabled(toggle)
        let original = toggle.value as? String
        toggle.tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in toggle.value as? String != original }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 6), .completed)
        let expected = toggle.value as? String
        app.terminate()
        app.launch()
        openReminders(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, expected)
    }

    @MainActor func testBlockedPermissionExplainsPhoneSettings() {
        let app = launch(permission: "blocked")
        defer { app.terminate() }
        openReminders(app)
        XCTAssertTrue(app.staticTexts["reminders.blocked"].waitForExistence(timeout: 8))
        let toggle = app.switches["reminders.enabled"]
        XCTAssertTrue(toggle.exists)
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0")
        let open = app.buttons["reminders.openSettings"]
        AuthUIFlow.reveal(open, in: app)
        XCTAssertTrue(open.isEnabled)
    }

    @MainActor func testAskPermissionAndFirstTripSeam() {
        let app = launch(permission: "undetermined", firstTrip: true)
        defer { app.terminate() }
        let enable = app.buttons["reminders.firstTrip.enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 12))
        AuthUIFlow.waitUntilEnabled(enable)
        enable.tap()
        openReminders(app)
        let toggle = app.switches["reminders.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertEqual(toggle.value as? String, "1")
    }

    @MainActor private func launch(permission: String, firstTrip: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments() + ["-cf.notificationAuthorization", permission]
        if firstTrip { app.launchArguments.append("-cf.firstTripReminders") }
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        return app
    }

    @MainActor private func openReminders(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 12))
        settings.tap()
        let row = app.buttons["settings.reminders"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        AuthUIFlow.reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reminders.screen"].firstMatch.waitForExistence(timeout: 8))
    }
}

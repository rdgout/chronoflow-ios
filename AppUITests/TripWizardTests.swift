import XCTest

nonisolated final class TripWizardTests: XCTestCase {
    private let dateAnchor = Date()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    @MainActor func testWhereWithStopTimesOneWaySleepAndChecking() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launchEnvironment["CF_WIZARD_TEST_REVIEW"] = "1"
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        app.tabBars.buttons["My trips"].tap()
        let create = app.buttons["trips.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.otherElements["wizard.where"].waitForExistence(timeout: 8))
        choose("AMS", side: "from", in: app)
        choose("HND", side: "to", in: app)
        app.segmentedControls["wizard.route.stops"].buttons["Yes"].tap()
        search("DXB", in: app)
        XCTAssertTrue(app.buttons["wizard.stop.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wizard.swap"].exists)
        app.buttons["wizard.where.continue"].tap()
        XCTAssertTrue(app.otherElements["wizard.outbound"].waitForExistence(timeout: 5))
        let firstDay = WizardPickerUIFlow.date(days: 30, from: dateAnchor)
        let nextDay = WizardPickerUIFlow.date(days: 31, from: dateAnchor)
        WizardPickerUIFlow.dateTime("departure", date: firstDay, hour: 14, minute: 40, in: app)
        WizardPickerUIFlow.dateTime("arrival", date: firstDay, displayed: firstDay, hour: 23, minute: 25, in: app)
        WizardPickerUIFlow.dateTime(
            "departure", index: 1, date: nextDay, displayed: firstDay, hour: 2, minute: 5, in: app)
        WizardPickerUIFlow.dateTime(
            "arrival", index: 1, date: nextDay, displayed: nextDay, hour: 16, minute: 35, in: app)
        app.buttons["wizard.outbound.continue"].tap()
        XCTAssertTrue(app.buttons["wizard.choice.one-way"].waitForExistence(timeout: 5))
        app.buttons["wizard.choice.one-way"].tap()
        let sleep = app.buttons["wizard.sleep.continue"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 6))
        app.buttons["wizard.choice.sleep.unsure"].tap()
        AuthUIFlow.waitUntilEnabled(sleep)
        sleep.tap()
        XCTAssertTrue(app.otherElements["wizard.checking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wizard.choice.question.18_64"].waitForExistence(timeout: 10))
    }

    @MainActor private func choose(_ code: String, side: String, in app: XCUIApplication) {
        let button = app.buttons["wizard.\(side)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        search(code, in: app)
    }

    @MainActor private func search(_ code: String, in app: XCUIApplication) {
        let search = app.descendants(matching: .any)["wizard.airport.query"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(code)
        let result = app.buttons["wizard.airport.\(code)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
    }
}

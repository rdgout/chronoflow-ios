import XCTest

nonisolated final class TripWizardReviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor func testOneWaySleepQuestionAndReviewReachPhase16c() throws {
        try journey(returnFlight: false)
    }

    @MainActor func testFlightHomeSleepQuestionAndReviewReachPhase16c() throws {
        try journey(returnFlight: true)
    }

    @MainActor func testFailedRequestUsesCheckOfflineAfterCachedRelaunch() throws {
        let app = launch()
        defer { app.terminate() }
        inputOutbound(app)
        app.buttons["wizard.choice.one-way"].tap()
        answerSleep(app)
        XCTAssertTrue(app.otherElements["wizard.question.0"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment["CF_AUTH_TEST_OFFLINE"] = "1"
        app.launch()
        let answer = app.buttons["wizard.choice.question.18_64"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15))
        answer.tap()
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["wizard.checking.continue"].isEnabled)
        XCTAssertFalse(app.otherElements["wizard.debug.continue"].exists)
        let back = app.navigationBars.buttons["Back"]
        XCTAssertTrue(back.exists)
        app.buttons["wizard.checking.secondary-close"].tap()
        XCTAssertTrue(app.alerts["Discard this trip?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].exists)
        back.tap()
        XCTAssertTrue(app.otherElements["wizard.sleep"].waitForExistence(timeout: 5))
    }

    @MainActor private func journey(returnFlight: Bool) throws {
        let app = launch()
        defer { app.terminate() }
        inputOutbound(app)
        let choice = app.buttons[returnFlight ? "wizard.choice.add-return" : "wizard.choice.one-way"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        if returnFlight {
            XCTAssertTrue(app.otherElements["wizard.return-flight"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["wizard.return-flight.from"].exists)
            date("departure", index: 1, day: "22", in: app)
            date("arrival", index: 1, day: "22", in: app)
            time("departure", index: 1, hour: "10", minute: "25", in: app)
            time("arrival", index: 1, hour: "15", minute: "30", in: app)
            app.buttons["wizard.return-flight.continue"].tap()
        }
        answerSleep(app)
        let answer = app.buttons["wizard.choice.question.18_64"]
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["Which age group are you in?"].label, "Which age group are you in?")
        answer.tap()
        XCTAssertTrue(app.otherElements["wizard.debug.continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Continue · Phase 16c (temporary)"].exists)
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = AuthUIFlow.arguments()
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
        app.launchEnvironment["CF_WIZARD_TEST_REVIEW"] = "1"
        app.launch()
        AuthUIFlow.openSignIn(app)
        AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        app.tabBars.buttons["My trips"].tap()
        return app
    }

    @MainActor private func inputOutbound(_ app: XCUIApplication) {
        let create = app.buttons["trips.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        chooseAirport("AMS", side: "from", in: app)
        chooseAirport("HND", side: "to", in: app)
        app.buttons["wizard.where.continue"].tap()
        date("departure", index: 0, day: "10", in: app)
        date("arrival", index: 0, day: "11", in: app)
        time("departure", index: 0, hour: "14", minute: "40", in: app)
        time("arrival", index: 0, hour: "9", minute: "15", in: app)
        app.buttons["wizard.outbound.continue"].tap()
        XCTAssertTrue(app.otherElements["wizard.return"].waitForExistence(timeout: 5))
    }

    @MainActor private func answerSleep(_ app: XCUIApplication) {
        let next = app.buttons["wizard.sleep.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        app.buttons["wizard.choice.sleep.unsure"].tap()
        AuthUIFlow.waitUntilEnabled(next)
        next.tap()
    }

    @MainActor private func chooseAirport(_ code: String, side: String, in app: XCUIApplication) {
        let button = app.buttons["wizard.\(side)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(code)
        let result = app.buttons["wizard.airport.\(code)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
    }

    @MainActor private func date(_ side: String, index: Int, day: String, in app: XCUIApplication) {
        let button = app.buttons["wizard.\(index).\(side).date"]
        AuthUIFlow.reveal(button, in: app, scroll: app.scrollViews.firstMatch)
        button.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 2).waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: "November")
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: day)
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: "2040")
        app.buttons["wizard.picker.done"].tap()
    }

    @MainActor private func time(_ side: String, index: Int, hour: String, minute: String, in app: XCUIApplication) {
        let picker = app.datePickers["wizard.\(index).\(side).time"]
        AuthUIFlow.reveal(picker, in: app, scroll: app.scrollViews.firstMatch)
        picker.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
        let numeric = Int(hour)!
        wheels.element(boundBy: 0).adjust(
            toPickerWheelValue: wheels.count == 3 ? String(numeric % 12 == 0 ? 12 : numeric % 12) : hour)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        if wheels.count == 3 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: numeric < 12 ? "AM" : "PM") }
        app.staticTexts[index == 0 ? "When is your flight?" : "Your flight home"].tap()
    }
}

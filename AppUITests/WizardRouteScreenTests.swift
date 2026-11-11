import XCTest

nonisolated final class WizardRouteScreenTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testStopRowsRemoveAndDirectClearsTheRoute() {
        let app = WizardScreenUIFlow.launch("WizardWhereStops")
        XCTAssertTrue(app.buttons["wizard.from"].exists)
        XCTAssertTrue(app.buttons["wizard.to"].exists)
        XCTAssertTrue(app.buttons["wizard.stop.1"].label.contains("Stop 1"))
        XCTAssertTrue(app.buttons["wizard.stop.2"].label.contains("Stop 2"))
        XCTAssertFalse(app.buttons["wizard.swap"].exists)
        app.buttons["wizard.remove-stop.2"].tap()
        XCTAssertFalse(app.buttons["wizard.stop.2"].exists)
        XCTAssertTrue(app.buttons["wizard.stop.1"].label.contains("DXB"))
        app.segmentedControls["wizard.route.stops"].buttons["No, direct"].tap()
        XCTAssertFalse(app.buttons["wizard.stop.1"].exists)
        XCTAssertTrue(app.buttons["wizard.swap"].exists)
        XCTAssertTrue(app.buttons["wizard.where.continue"].isEnabled)
        app.segmentedControls["wizard.route.stops"].buttons["Yes"].tap()
        XCTAssertTrue(app.otherElements["wizard.airport-search"].waitUntil(.exists, timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.segmentedControls["wizard.route.stops"].buttons["No, direct"].isSelected)
    }

    @MainActor func testDirectRouteShowsSwapAndContinue() {
        let app = WizardScreenUIFlow.launch("WizardWhere")
        XCTAssertTrue(app.buttons["wizard.where.continue"].isEnabled)
        XCTAssertTrue(app.buttons["wizard.swap"].exists)
    }

    @MainActor func testSameAirportShowsErrorAndDisablesContinue() {
        let app = WizardScreenUIFlow.launch("WizardWhereSame")
        XCTAssertFalse(app.buttons["wizard.where.continue"].isEnabled)
        XCTAssertTrue(app.staticTexts["wizard.where.same"].exists)
        XCTAssertFalse(app.segmentedControls["wizard.route.stops"].exists)
        XCTAssertFalse(app.staticTexts["From your last trip"].exists)
    }

    @MainActor func testRouteLimitReplacesAddStop() {
        let app = WizardScreenUIFlow.launch("WizardWhereLimit")
        let limit = app.staticTexts["wizard.route.limit"]
        AuthUIFlow.reveal(limit, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertTrue(limit.isHittable)
        XCTAssertFalse(app.buttons["wizard.add-stop"].exists)
        XCTAssertTrue(app.buttons["wizard.where.continue"].isHittable)
        XCTAssertTrue(app.buttons["wizard.where.continue"].isEnabled)
    }

    @MainActor func testDirectHomeRouteLocksFrom() { assertHomeRoute("WizardHomeRoute") }
    @MainActor func testHomeRouteWithStopLocksFrom() { assertHomeRoute("WizardHomeRouteStop") }

    @MainActor private func assertHomeRoute(_ board: String) {
        let app = WizardScreenUIFlow.launch(board)
        XCTAssertTrue(app.otherElements["wizard.return-route"].waitUntil(.exists, timeout: 3))
        let origin = app.buttons["wizard.from"]
        XCTAssertFalse(origin.isEnabled)
        XCTAssertTrue(origin.label.contains("where you landed"))
        XCTAssertTrue(app.buttons["wizard.to"].label.contains("AMS"))
        XCTAssertFalse(app.buttons["wizard.swap"].exists)
        XCTAssertEqual(app.buttons["wizard.stop.1"].exists, board == "WizardHomeRouteStop")
        XCTAssertTrue(app.buttons["wizard.return-route.continue"].isEnabled)
    }

    @MainActor func testThreeFlightsScrollWithContinuePinned() {
        let app = WizardScreenUIFlow.launch("WizardOutboundThree")
        let next = app.buttons["wizard.outbound.continue"]
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(next.isEnabled)
        let last = app.buttons["wizard.2.arrival.date-time"]
        AuthUIFlow.reveal(last, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(next.frame))
        XCTAssertFalse(app.buttons["wizard.add-stop"].exists)
        XCTAssertFalse(app.buttons["wizard.remove-stop.1"].exists)
    }

    @MainActor func testBoardErrorAppearsOnlyUnderTheSecondFlight() {
        let app = WizardScreenUIFlow.launch("WizardOutboundTwoErrors")
        let error = app.staticTexts["wizard.1.arrival.error"]
        AuthUIFlow.reveal(error, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertEqual(error.label, "Check the departure and arrival times.")
        XCTAssertFalse(app.staticTexts["wizard.0.departure.error"].exists)
        XCTAssertFalse(app.staticTexts["wizard.0.arrival.error"].exists)
        XCTAssertFalse(app.staticTexts["wizard.1.departure.error"].exists)
    }

    @MainActor func testContinueScrollsBackToTheOffscreenFirstError() {
        let app = WizardScreenUIFlow.launch("WizardOutboundScrollErrors")
        let first = app.staticTexts["wizard.0.arrival.error"]
        let later = app.staticTexts["wizard.4.departure.error"]
        let next = app.buttons["wizard.outbound.continue"]
        AuthUIFlow.reveal(later, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertTrue(
            UIWait.until(timeout: 3) {
                later.exists && first.exists && !first.frame.isEmpty && !first.isHittable
                    && next.exists && next.isHittable && next.isEnabled
            })
        XCTAssertEqual(later.label, "This flight leaves before the previous one lands.")
        next.tap()
        XCTAssertTrue(first.waitUntil(.hittable, timeout: 3))
    }

    @MainActor func testEmptyArrivalPickerStartsOnTheSetDepartureDate() {
        let app = WizardScreenUIFlow.launch("WizardOutboundStopNew")
        let arrival = app.buttons["wizard.0.arrival.date-time"]
        XCTAssertEqual(arrival.value as? String, "not set")
        _ = WizardPickerUIFlow.open("arrival", in: app)
        app.buttons["wizard.picker.done"].tap()
        let value = arrival.value as? String ?? ""
        XCTAssertTrue(value.contains("12 Oct") || value.contains("Oct 12"), value)
        XCTAssertTrue(value.contains("16:40") || value.contains("4:40"), value)
    }

    @MainActor func testEmptyPickerCancelKeepsThePillUnset() { assertPicker(board: "WizardOutboundEmpty", save: false) }
    @MainActor func testEmptyPickerDoneSetsThePill() { assertPicker(board: "WizardOutboundEmpty", save: true) }
    @MainActor func testFilledPickerCancelKeepsThePill() { assertPicker(board: "WizardOutbound", save: false) }
    @MainActor func testFilledPickerDoneUpdatesThePill() { assertPicker(board: "WizardOutbound", save: true) }

    @MainActor private func assertPicker(board: String, save: Bool) {
        let app = WizardScreenUIFlow.launch(board)
        let pill = app.buttons["wizard.0.departure.date-time"]
        let original = pill.value as? String
        let picker = WizardPickerUIFlow.open("departure", in: app)
        XCTAssertTrue(app.navigationBars["Departure"].exists)
        let displayed = board == "WizardOutboundEmpty" ? Date() : WizardPickerUIFlow.seededDeparture
        let tomorrow = WizardPickerUIFlow.date(days: 1, from: displayed)
        WizardPickerUIFlow.selectDate(tomorrow, from: displayed, picker: picker)
        app.buttons[save ? "wizard.picker.done" : "wizard.picker.cancel"].tap()
        if save {
            XCTAssertNotEqual(pill.value as? String, original)
        } else {
            XCTAssertEqual(pill.value as? String, original)
        }
    }
}

nonisolated final class WizardRouteDutchScreenTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testOneStopUsesDutchCopyAndTheNextSearchNamesItsEndpoints() {
        let app = WizardScreenUIFlow.launch("WizardWhereStop", language: "nl")
        XCTAssertTrue(app.buttons["wizard.stop.1"].label.hasPrefix("Tussenstop,"))
        XCTAssertTrue(app.segmentedControls["wizard.route.stops"].buttons["Ja"].isSelected)
        let add = app.buttons["wizard.add-stop"]
        XCTAssertEqual(add.label, "Nog een tussenstop toevoegen")
        add.tap()
        XCTAssertTrue(app.otherElements["wizard.airport-search"].waitUntil(.exists, timeout: 5))
        XCTAssertTrue(app.staticTexts["Tussen Dubai en Tokio"].exists)
    }

    @MainActor func testEmptyPillsAnnounceNotSetInDutch() {
        let app = WizardScreenUIFlow.launch("WizardOutboundEmpty", language: "nl")
        XCTAssertEqual(app.buttons["wizard.0.departure.date-time"].value as? String, "niet ingesteld")
        XCTAssertEqual(app.buttons["wizard.0.arrival.date-time"].value as? String, "niet ingesteld")
    }

}

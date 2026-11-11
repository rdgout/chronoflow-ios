import XCTest

nonisolated final class TripWizardReviewTests: ScreenTestCase {
    override func setUp() async throws {
        try await super.setUp()
        executionTimeAllowance = 60
    }

    @MainActor func testFlightHomeTimesContainsOnlyFlightCards() {
        let app = WizardScreenUIFlow.launch("WizardReturnFlight")
        XCTAssertTrue(app.otherElements["wizard.return-flight"].waitUntil(.exists, timeout: 5))
        XCTAssertEqual(app.staticTexts["wizard.title"].label, "When do you fly home?")
        XCTAssertTrue(app.buttons["wizard.1.departure.date-time"].exists)
        XCTAssertTrue(app.buttons["wizard.1.arrival.date-time"].exists)
        XCTAssertFalse(app.buttons["wizard.to"].exists)
        XCTAssertFalse(app.buttons["wizard.return-flight.add-stop"].exists)
        XCTAssertFalse(app.buttons["wizard.return-flight.continue"].isEnabled)
    }

    @MainActor func testPastOutboundArrivalNoticeStaysOnTimes() {
        assertPastArrival("WizardOutboundPast", step: "outbound")
    }
    @MainActor func testPastReturnArrivalNoticeStaysOnTimes() {
        assertPastArrival("WizardReturnFlightPast", step: "return-flight")
    }

    @MainActor private func assertPastArrival(_ board: String, step: String) {
        let app = WizardScreenUIFlow.launch(board)
        XCTAssertTrue(app.staticTexts["wizard.\(step).past"].waitUntil(.exists, timeout: 3))
        XCTAssertTrue(app.buttons["wizard.\(step).continue"].isEnabled)
    }

    @MainActor func testCheckOfflineScreenKeepsEditingAndGoesBack() {
        let app = WizardScreenUIFlow.launch("WizardCheckOffline")
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].waitUntil(.exists, timeout: 8))
        XCTAssertTrue(app.buttons["wizard.checking.continue"].isEnabled)
        XCTAssertFalse(app.buttons["wizard.debug.continue"].exists)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.exists)
        app.buttons["wizard.checking.secondary-close"].tap()
        XCTAssertTrue(app.alerts["Discard this trip?"].waitUntil(.exists, timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].exists)
        back.tap()
        XCTAssertTrue(app.otherElements["wizard.return"].waitUntil(.exists, timeout: 5))
    }
}

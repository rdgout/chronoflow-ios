import XCTest

nonisolated final class TripWizardReviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor func testFlightHomeTimesContainsOnlyFlightCards() {
        let app = WizardScreenUIFlow.launch("WizardReturnFlight")
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["wizard.return-flight"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["wizard.title"].label, "When do you fly home?")
        XCTAssertTrue(app.buttons["wizard.1.departure.date-time"].exists)
        XCTAssertTrue(app.buttons["wizard.1.arrival.date-time"].exists)
        XCTAssertFalse(app.buttons["wizard.to"].exists)
        XCTAssertFalse(app.buttons["wizard.return-flight.add-stop"].exists)
        XCTAssertFalse(app.buttons["wizard.return-flight.continue"].isEnabled)
    }

    @MainActor func testPastArrivalNoticeStaysOnTimes() {
        for board in ["WizardOutboundPast", "WizardReturnFlightPast"] {
            let app = WizardScreenUIFlow.launch(board)
            defer { app.terminate() }
            let id = board == "WizardOutboundPast" ? "outbound" : "return-flight"
            XCTAssertTrue(app.descendants(matching: .any)["wizard.\(id).past"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["wizard.\(id).continue"].isEnabled)
        }
    }

    @MainActor func testCheckOfflineScreenKeepsEditingAndGoesBack() {
        let app = WizardScreenUIFlow.launch("WizardCheckOffline")
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["wizard.checking.continue"].isEnabled)
        XCTAssertFalse(app.otherElements["wizard.debug.continue"].exists)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.exists)
        app.buttons["wizard.checking.secondary-close"].tap()
        XCTAssertTrue(app.alerts["Discard this trip?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Keep editing"].tap()
        XCTAssertTrue(app.otherElements["wizard.checking.offline"].exists)
        back.tap()
        XCTAssertTrue(app.otherElements["wizard.return"].waitForExistence(timeout: 5))
    }
}

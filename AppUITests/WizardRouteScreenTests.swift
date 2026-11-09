import XCTest

nonisolated final class WizardRouteScreenTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor func testStopRowsRemoveAndDirectClearsTheRoute() {
        let app = WizardScreenUIFlow.launch("WizardWhereStops")
        defer { app.terminate() }
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
        XCTAssertTrue(app.otherElements["wizard.airport-search"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.segmentedControls["wizard.route.stops"].buttons["No, direct"].isSelected)
    }

    @MainActor func testDirectSameAndLimitScreens() {
        for board in ["WizardWhere", "WizardWhereSame", "WizardWhereLimit"] {
            let app = WizardScreenUIFlow.launch(board)
            defer { app.terminate() }
            let next = app.buttons["wizard.where.continue"]
            if board == "WizardWhereSame" {
                XCTAssertFalse(next.isEnabled)
                XCTAssertTrue(app.descendants(matching: .any)["wizard.where.same"].exists)
                XCTAssertFalse(app.segmentedControls["wizard.route.stops"].exists)
            } else if board == "WizardWhereLimit" {
                let limit = app.staticTexts["wizard.route.limit"]
                AuthUIFlow.reveal(limit, in: app, scroll: app.scrollViews.firstMatch)
                XCTAssertTrue(limit.isHittable)
                XCTAssertFalse(app.buttons["wizard.add-stop"].exists)
                XCTAssertTrue(next.isHittable && next.isEnabled)
            } else {
                XCTAssertTrue(next.isEnabled)
                XCTAssertTrue(app.buttons["wizard.swap"].exists)
            }
        }
    }

    @MainActor func testOneStopUsesDutchCopyAndTheNextSearchNamesItsEndpoints() {
        let app = WizardScreenUIFlow.launch("WizardWhereStop", language: "nl")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["wizard.stop.1"].label.hasPrefix("Tussenstop,"))
        XCTAssertTrue(app.segmentedControls["wizard.route.stops"].buttons["Ja"].isSelected)
        let add = app.buttons["wizard.add-stop"]
        XCTAssertEqual(add.label, "Nog een tussenstop toevoegen")
        add.tap()
        XCTAssertTrue(app.otherElements["wizard.airport-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tussen Dubai en Tokio"].exists)
    }

    @MainActor func testHomeRouteLocksFromAndShowsItsStops() {
        for board in ["WizardHomeRoute", "WizardHomeRouteStop"] {
            let app = WizardScreenUIFlow.launch(board)
            defer { app.terminate() }
            XCTAssertTrue(app.otherElements["wizard.return-route"].waitForExistence(timeout: 5))
            let origin = app.buttons["wizard.from"]
            XCTAssertFalse(origin.isEnabled)
            XCTAssertTrue(origin.label.contains("where you landed"))
            XCTAssertTrue(app.buttons["wizard.to"].label.contains("AMS"))
            XCTAssertFalse(app.buttons["wizard.swap"].exists)
            XCTAssertEqual(app.buttons["wizard.stop.1"].exists, board == "WizardHomeRouteStop")
            XCTAssertTrue(app.buttons["wizard.return-route.continue"].isEnabled)
        }
    }

    @MainActor func testThreeFlightsScrollWithContinuePinned() {
        let app = WizardScreenUIFlow.launch("WizardOutboundThree")
        defer { app.terminate() }
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

    @MainActor func testTwoErrorsRemainUnderTheirCardsAndContinueReturnsToTheFirst() throws {
        let app = WizardScreenUIFlow.launch("WizardOutboundTwoErrors")
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["wizard.0.arrival.error"].exists)
        let later = app.descendants(matching: .any)["wizard.1.departure.error"]
        AuthUIFlow.reveal(later, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertEqual(later.label, "This flight leaves before the previous one lands.")
        app.buttons["wizard.outbound.continue"].tap()
        let first = app.descendants(matching: .any)["wizard.0.arrival.error"]
        _ = try UIWait.stableFrames([first], timeout: 5)
        XCTAssertTrue(first.isHittable)
    }

    @MainActor func testEmptyAndFilledPickerShareTheSheetAndOnlyDoneWrites() {
        let app = WizardScreenUIFlow.launch("WizardOutboundEmpty")
        defer { app.terminate() }
        let pill = app.buttons["wizard.0.departure.date-time"]
        XCTAssertEqual(pill.value as? String, "Choose")
        let picker = WizardPickerUIFlow.open("departure", in: app)
        let title = app.navigationBars["Departure"]
        XCTAssertTrue(title.exists)
        let tomorrow = WizardPickerUIFlow.date(days: 1, from: Date())
        WizardPickerUIFlow.selectDate(tomorrow, picker: picker)
        app.buttons["wizard.picker.cancel"].tap()
        XCTAssertEqual(pill.value as? String, "Choose")
        _ = WizardPickerUIFlow.open("departure", in: app)
        XCTAssertTrue(title.exists)
        app.buttons["wizard.picker.done"].tap()
        let committed = pill.value as? String
        XCTAssertNotEqual(committed, "Choose")
        let filled = WizardPickerUIFlow.open("departure", in: app)
        XCTAssertTrue(title.exists)
        WizardPickerUIFlow.selectDate(tomorrow, picker: filled)
        app.buttons["wizard.picker.cancel"].tap()
        XCTAssertEqual(pill.value as? String, committed)
        let reopened = WizardPickerUIFlow.open("departure", in: app)
        WizardPickerUIFlow.selectDate(tomorrow, picker: reopened)
        app.buttons["wizard.picker.done"].tap()
        XCTAssertNotEqual(pill.value as? String, committed)
    }
}

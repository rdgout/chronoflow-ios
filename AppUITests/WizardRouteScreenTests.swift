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
                XCTAssertTrue(app.staticTexts["wizard.where.same"].exists)
                XCTAssertFalse(app.segmentedControls["wizard.route.stops"].exists)
                XCTAssertFalse(app.staticTexts["From your last trip"].exists)
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

    @MainActor func testBoardErrorAppearsOnlyUnderTheSecondFlight() {
        let app = WizardScreenUIFlow.launch("WizardOutboundTwoErrors")
        defer { app.terminate() }
        let error = app.staticTexts["wizard.1.arrival.error"]
        AuthUIFlow.reveal(error, in: app, scroll: app.scrollViews.firstMatch)
        XCTAssertEqual(error.label, "Check the departure and arrival times.")
        for identifier in ["wizard.0.departure.error", "wizard.0.arrival.error", "wizard.1.departure.error"] {
            XCTAssertFalse(app.staticTexts[identifier].exists)
        }
    }

    @MainActor func testContinueScrollsBackToTheOffscreenFirstError() {
        let app = WizardScreenUIFlow.launch("WizardOutboundScrollErrors")
        defer { app.terminate() }
        let scroll = app.scrollViews.firstMatch
        let first = app.staticTexts["wizard.0.arrival.error"]
        let later = app.staticTexts["wizard.4.departure.error"]
        let next = app.buttons["wizard.outbound.continue"]
        let footer = app.otherElements["wizard.outbound.footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        func visible(_ error: XCUIElement) -> Bool {
            guard error.exists else { return false }
            let frame = error.frame
            let footerFrame = footer.frame
            let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
            return !frame.isEmpty && !footerFrame.isEmpty && viewport.contains(frame)
                && frame.maxY <= footerFrame.minY
        }
        let atBottom = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                visible(later) && first.exists && first.frame.maxY < scroll.frame.minY
            }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [atBottom], timeout: 5), .completed)
        XCTAssertEqual(later.label, "This flight leaves before the previous one lands.")
        XCTAssertLessThan(first.frame.maxY, scroll.frame.minY)
        XCTAssertTrue(next.isHittable && next.isEnabled)
        next.tap()
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in visible(first) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        XCTAssertTrue(visible(first))
    }

    @MainActor func testEmptyPillsAnnounceNotSetInDutch() {
        let app = WizardScreenUIFlow.launch("WizardOutboundEmpty", language: "nl")
        defer { app.terminate() }
        for side in ["departure", "arrival"] {
            XCTAssertEqual(app.buttons["wizard.0.\(side).date-time"].value as? String, "niet ingesteld")
        }
    }

    @MainActor func testEmptyArrivalPickerStartsOnTheSetDepartureDate() {
        let app = WizardScreenUIFlow.launch("WizardOutboundStopNew")
        defer { app.terminate() }
        let arrival = app.buttons["wizard.0.arrival.date-time"]
        XCTAssertEqual(arrival.value as? String, "not set")
        _ = WizardPickerUIFlow.open("arrival", in: app)
        app.buttons["wizard.picker.done"].tap()
        let value = arrival.value as? String ?? ""
        XCTAssertTrue(value.contains("12 Oct") || value.contains("Oct 12"), value)
        XCTAssertTrue(value.contains("16:40") || value.contains("4:40"), value)
    }

    @MainActor func testEmptyAndFilledPickerShareTheSheetAndOnlyDoneWrites() {
        let app = WizardScreenUIFlow.launch("WizardOutboundEmpty")
        defer { app.terminate() }
        let pill = app.buttons["wizard.0.departure.date-time"]
        XCTAssertEqual(pill.value as? String, "not set")
        let picker = WizardPickerUIFlow.open("departure", in: app)
        let title = app.navigationBars["Departure"]
        XCTAssertTrue(title.exists)
        let tomorrow = WizardPickerUIFlow.date(days: 1, from: Date())
        WizardPickerUIFlow.selectDate(tomorrow, picker: picker)
        app.buttons["wizard.picker.cancel"].tap()
        XCTAssertEqual(pill.value as? String, "not set")
        _ = WizardPickerUIFlow.open("departure", in: app)
        XCTAssertTrue(title.exists)
        app.buttons["wizard.picker.done"].tap()
        let committed = pill.value as? String
        XCTAssertNotEqual(committed, "not set")
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

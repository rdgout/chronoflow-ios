import XCTest

nonisolated final class TripWizardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor func testEntryAirportSearchNativeTimesErrorsAndPastArrival() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        app.tabBars.buttons["My trips"].tap()
        openWizard(app)
        choose("AMS", side: "from", in: app)
        choose("HND", side: "to", in: app)
        let next = app.buttons["wizard.where.continue"]
        AuthUIFlow.waitUntilEnabled(next)
        next.tap()
        XCTAssertTrue(app.otherElements["wizard.outbound"].waitForExistence(timeout: 5))
        pickEmptyDate("departure", month: "November", day: "10", year: "2040", in: app)
        pickTime("departure", hour: "14", minute: "40", in: app)
        pickEmptyDate("arrival", month: "November", day: "9", year: "2040", in: app)
        pickTime("arrival", hour: "9", minute: "15", in: app)
        app.buttons["wizard.outbound.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["wizard.0.arrival.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outbound.past"].exists)
        closeAndDiscard(app)

        openWizard(app)
        choose("AMS", side: "from", in: app)
        choose("HND", side: "to", in: app)
        app.buttons["wizard.where.continue"].tap()
        pickEmptyDate("departure", month: "November", day: "10", year: "2001", in: app)
        pickTime("departure", hour: "14", minute: "40", in: app)
        pickEmptyDate("arrival", month: "November", day: "11", year: "2001", in: app)
        pickTime("arrival", hour: "9", minute: "15", in: app)
        app.buttons["wizard.outbound.continue"].tap()
        XCTAssertTrue(app.buttons["wizard.choice.one-way"].waitForExistence(timeout: 5))
        app.buttons["wizard.choice.one-way"].tap()
        let sleep = app.buttons["wizard.sleep.continue"]
        if sleep.waitForExistence(timeout: 2) {
            app.buttons["wizard.choice.sleep.unsure"].tap()
            AuthUIFlow.waitUntilEnabled(sleep)
            sleep.tap()
        }
        let past = app.descendants(matching: .any)["wizard.outbound.past"]
        XCTAssertTrue(past.waitForExistence(timeout: 5))
        XCTAssertEqual(
            past.label,
            "A new plan needs an upcoming arrival. Check your flight dates or add your return flight.")
        XCTAssertTrue(app.buttons["wizard.outbound.continue"].isEnabled)
        closeAndDiscard(app)
    }

    @MainActor private func openWizard(_ app: XCUIApplication) {
        let add = app.buttons["trips.create"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.otherElements["wizard.where"].waitForExistence(timeout: 8))
    }

    @MainActor private func choose(_ code: String, side: String, in app: XCUIApplication) {
        app.buttons["wizard.\(side)"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(code)
        let result = app.buttons["wizard.airport.\(code)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.buttons["wizard.\(side)"].waitForExistence(timeout: 5))
    }

    @MainActor private func pickEmptyDate(
        _ side: String, month: String, day: String, year: String, in app: XCUIApplication
    ) {
        let button = app.buttons["wizard.0.\(side).date"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.element(boundBy: 2).waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: day)
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: year)
        app.buttons["wizard.picker.done"].tap()
    }

    @MainActor private func pickTime(_ side: String, hour: String, minute: String, in app: XCUIApplication) {
        let picker = app.datePickers["wizard.0.\(side).time"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
        let numericHour = Int(hour)!
        let displayedHour = wheels.count == 3 ? String(numericHour % 12 == 0 ? 12 : numericHour % 12) : hour
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: displayedHour)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        if wheels.count == 3 { wheels.element(boundBy: 2).adjust(toPickerWheelValue: numericHour < 12 ? "AM" : "PM") }
        app.staticTexts["When is your flight?"].tap()
    }

    @MainActor private func closeAndDiscard(_ app: XCUIApplication) {
        app.buttons["wizard.close"].tap()
        let discard = app.alerts.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 4))
        discard.tap()
        XCTAssertTrue(app.buttons["trips.create"].waitForExistence(timeout: 5))
    }
}

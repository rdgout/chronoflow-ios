import XCTest

nonisolated final class TripWizardTests: XCTestCase {
    private let dateAnchor = Date()

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
        WizardPickerUIFlow.emptyDate("departure", date: WizardPickerUIFlow.date(days: 30, from: dateAnchor), in: app)
        WizardPickerUIFlow.time("departure", hour: "14", minute: "40", in: app)
        WizardPickerUIFlow.emptyDate("arrival", date: WizardPickerUIFlow.date(days: 29, from: dateAnchor), in: app)
        WizardPickerUIFlow.time("arrival", hour: "9", minute: "15", in: app)
        app.buttons["wizard.outbound.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["wizard.0.arrival.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["wizard.outbound.past"].exists)
        WizardPickerUIFlow.time("arrival", hour: "10", minute: "25", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["wizard.0.arrival.error"].exists)
        closeAndDiscard(app)

        openWizard(app)
        choose("AMS", side: "from", in: app)
        choose("HND", side: "to", in: app)
        app.buttons["wizard.where.continue"].tap()
        WizardPickerUIFlow.emptyDate("departure", date: WizardPickerUIFlow.date(days: -30, from: dateAnchor), in: app)
        WizardPickerUIFlow.time("departure", hour: "14", minute: "40", in: app)
        WizardPickerUIFlow.emptyDate("arrival", date: WizardPickerUIFlow.date(days: -29, from: dateAnchor), in: app)
        WizardPickerUIFlow.time("arrival", hour: "9", minute: "15", in: app)
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
        let search = app.descendants(matching: .any)["wizard.airport.query"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(code)
        let result = app.buttons["wizard.airport.\(code)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.buttons["wizard.\(side)"].waitForExistence(timeout: 5))
    }

    @MainActor private func closeAndDiscard(_ app: XCUIApplication) {
        app.buttons["wizard.close"].tap()
        let discard = app.alerts.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 4))
        discard.tap()
        XCTAssertTrue(app.buttons["trips.create"].waitForExistence(timeout: 5))
    }
}

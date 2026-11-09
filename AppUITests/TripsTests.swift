import XCTest

nonisolated final class TripsTests: XCTestCase {
    @MainActor func testTripsSectionsRefreshAndOpenOneTripRoute() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        app.tabBars.buttons["My trips"].tap()
        let screen = app.scrollViews["trips.screen"]
        XCTAssertTrue(screen.waitForMeasuredExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["trips.section.active"].waitForMeasuredExistence(timeout: 6))
        screen.swipeDown()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trip.")).firstMatch
        XCTAssertTrue(card.waitForMeasuredExistence(timeout: 6))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitForMeasuredExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForMeasuredExistence(timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(screen.waitForMeasuredExistence(timeout: 4))
    }
}

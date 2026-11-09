import XCTest

nonisolated final class TripsTests: XCTestCase {
    @MainActor func testTripsSectionsRefreshAndOpenOneTripRoute() {
        let app = launchPlanAccount()
        defer { app.terminate() }
        app.tabBars.buttons["My trips"].tap()
        let screen = app.scrollViews["trips.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["trips.section.active"].waitForExistence(timeout: 6))
        screen.swipeDown()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trip.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForExistence(timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(screen.waitForExistence(timeout: 4))
    }
}

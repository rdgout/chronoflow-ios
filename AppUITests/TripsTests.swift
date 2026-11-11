import XCTest

nonisolated final class TripsTests: ScreenTestCase {
    @MainActor func testTripsSectionsRefreshAndOpenOneTripRoute() throws {
        let app = try launchPlanAccount()
        app.tabBars.buttons["My trips"].tap()
        let screen = app.scrollViews["trips.screen"]
        XCTAssertTrue(screen.waitUntil(.exists, timeout: 12))
        XCTAssertTrue(app.staticTexts["trips.section.active"].waitUntil(.exists, timeout: 6))
        screen.swipeDown()
        let card = screen.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "trip.")).firstMatch
        XCTAssertTrue(card.waitUntil(.exists, timeout: 6))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitUntil(.exists, timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(screen.waitUntil(.exists, timeout: 4))
    }
}

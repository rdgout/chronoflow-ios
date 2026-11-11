import XCTest

nonisolated final class TripsTests: ScreenTestCase {
    @MainActor func testTripCardOpensTripRouteAndPops() throws {
        let app = try launchPlanAccount(route: "trips")
        let card = app.buttons["trip.\(PlanUIFlow.tripID)"]
        XCTAssertTrue(card.waitUntil(.hittable, timeout: 4))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 4))
        app.navigationBars.buttons["My trips"].tap()
        XCTAssertTrue(app.scrollViews["trips.screen"].waitUntil(.exists, timeout: 4))
    }
}

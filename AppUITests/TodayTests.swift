import XCTest

nonisolated final class TodayTests: ScreenTestCase {
    @MainActor func testTodayOpensTheTripRouteAndReturnsToItsRows() throws {
        let app = try launchPlanAccount(readyButton: "today.trip")
        app.buttons["today.trip"].tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 4))
        app.navigationBars.buttons["Today"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 4))
    }
}

nonisolated final class StepSheetScreenTests: ScreenTestCase {
    @MainActor func testDoneShowsUndo() throws {
        let app = try launchPlanAccount(freezePlanClock: true, stepID: PlanUIFlow.stepID)
        let done = app.buttons["step.done"]
        XCTAssertTrue(done.waitUntil(.hittable, timeout: 3))
        done.tap()
        XCTAssertTrue(app.buttons["step.undo"].waitUntil(.hittable, timeout: 3))
    }
}

nonisolated final class LegendTests: ScreenTestCase {
    @MainActor func testLegendClosesToToday() throws {
        let app = try launchPlanAccount(presentLegend: true)
        let close = app.buttons["legend.close"]
        XCTAssertTrue(close.waitUntil(.hittable, timeout: 3))
        close.tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 4))
    }
}

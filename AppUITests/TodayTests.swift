import XCTest

@MainActor func launchPlanAccount(
    presentLegend: Bool = false, freezePlanClock: Bool = false,
    updateTripOnRefresh: Bool = false, emptyTrips: Bool = false, refreshCounter: Bool = false,
    appearance: XCUIDevice.Appearance? = nil
) throws -> XCUIApplication {
    let app = ScreenTestApp.makeApplication()
    app.launchArguments = AuthUIFlow.arguments()
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
    if let appearance { app.launchArguments += ["-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light"] }
    if presentLegend { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "legend" }
    if freezePlanClock { app.launchEnvironment["CF_PLAN_TEST_FREEZE_CLOCK"] = "1" }
    if updateTripOnRefresh { app.launchEnvironment["CF_REFRESH_TEST_UPDATE_TRIP"] = "1" }
    if emptyTrips { app.launchEnvironment["CF_REFRESH_TEST_EMPTY_TRIPS"] = "1" }
    if refreshCounter { app.launchEnvironment["CF_REFRESH_TEST_COUNTER"] = "1" }
    AuthUIFlow.launchSignedIn(app, walkthroughSeen: true)
    do {
        let screen = app.scrollViews[presentLegend ? "legend.sheet" : "today.screen"]
        _ = try XCTUnwrap(
            screen.waitUntil(.exists, timeout: 15) ? screen : nil,
            "Expected seeded plan account to bypass Walkthrough and open \(screen.identifier)")
        if !presentLegend && !emptyTrips {
            let trip = app.buttons["today.trip"]
            _ = try XCTUnwrap(trip.waitUntil(.exists, timeout: 15) ? trip : nil, "Expected seeded Today trip")
        }
    } catch {
        app.terminate()
        throw error
    }
    return app
}

nonisolated final class TodayTests: ScreenTestCase {
    @MainActor func testTodayOpensTheTripRouteAndReturnsToItsRows() throws {
        let app = try launchPlanAccount()
        let card = app.buttons["today.trip"]
        XCTAssertTrue(card.waitUntil(.exists, timeout: 12))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitUntil(.exists, timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitUntil(.exists, timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 4))
    }
}

nonisolated final class StepSheetTests: ScreenTestCase {
    @MainActor func testTodayStepButtonsShowDoneUndoAndSkipStates() throws {
        let app = try launchPlanAccount()
        let row = app.scrollViews["today.screen"].buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable.")
        )
        .firstMatch
        XCTAssertTrue(row.waitUntil(.exists, timeout: 12))
        AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
        row.tap()
        let done = app.buttons["step.done"]
        XCTAssertTrue(app.scrollViews["step.sheet"].waitUntil(.exists, timeout: 4), app.debugDescription)
        XCTAssertTrue(done.waitUntil(.exists, timeout: 4))
        AuthUIFlow.reveal(done, in: app, scroll: app.scrollViews["step.sheet"])
        done.tap()
        let undo = app.buttons["step.undo"]
        XCTAssertTrue(undo.waitUntil(.exists, timeout: 6))
        undo.tap()
        let skip = app.buttons["step.skip"]
        XCTAssertTrue(skip.waitUntil(.exists, timeout: 6))
        skip.tap()
        XCTAssertTrue(undo.waitUntil(.exists, timeout: 6))
    }
}

nonisolated final class LegendTests: ScreenTestCase {
    @MainActor func testLegendCanScrollAndCloseToToday() throws {
        let app = try launchPlanAccount(presentLegend: true)
        app.scrollViews["legend.sheet"].swipeUp()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 4))
    }
}

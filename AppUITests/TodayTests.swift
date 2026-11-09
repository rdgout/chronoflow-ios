import XCTest

@MainActor func launchPlanAccount(
    presentLegend: Bool = false, freezePlanClock: Bool = false,
    updateTripOnRefresh: Bool = false, emptyTrips: Bool = false
) throws -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = AuthUIFlow.arguments()
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
    if presentLegend { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "legend" }
    if freezePlanClock { app.launchEnvironment["CF_PLAN_TEST_FREEZE_CLOCK"] = "1" }
    if updateTripOnRefresh { app.launchEnvironment["CF_REFRESH_TEST_UPDATE_TRIP"] = "1" }
    if emptyTrips { app.launchEnvironment["CF_REFRESH_TEST_EMPTY_TRIPS"] = "1" }
    app.launch()
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
    do {
        let screen = app.scrollViews[presentLegend ? "legend.sheet" : "today.screen"]
        _ = try XCTUnwrap(
            screen.waitForExistence(timeout: 15) ? screen : nil,
            "Expected seeded plan account to bypass Walkthrough and open \(screen.identifier)")
        if !presentLegend && !emptyTrips {
            let trip = app.buttons["today.trip"]
            _ = try XCTUnwrap(trip.waitForExistence(timeout: 15) ? trip : nil, "Expected seeded Today trip")
        }
    } catch {
        app.terminate()
        throw error
    }
    return app
}

nonisolated final class TodayTests: XCTestCase {
    @MainActor func testTodayOpensTheTripRouteAndReturnsToItsRows() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        let card = app.buttons["today.trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 12))
        card.tap()
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForExistence(timeout: 12))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}

nonisolated final class StepSheetTests: XCTestCase {
    @MainActor func testTodayStepCanBeDoneUndoneSkippedAndReopened() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        let identifier = row.identifier
        AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
        row.tap()
        let done = app.buttons["step.done"]
        XCTAssertTrue(app.scrollViews["step.sheet"].waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(done.waitForExistence(timeout: 4))
        AuthUIFlow.reveal(done, in: app, scroll: app.scrollViews["step.sheet"])
        done.tap()
        let undo = app.buttons["step.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 6))
        undo.tap()
        let skip = app.buttons["step.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 6))
        skip.tap()
        XCTAssertTrue(undo.waitForExistence(timeout: 6))
        let sheet = app.scrollViews["step.sheet"]
        for _ in 0..<4 where sheet.exists {
            sheet.swipeDown()
            if sheet.waitForNonExistence(timeout: 1) { break }
        }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 4), app.debugDescription)
        let reopened = app.buttons[identifier]
        AuthUIFlow.reveal(reopened, in: app, scroll: app.scrollViews["today.screen"])
        reopened.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(undo.waitForExistence(timeout: 6))
    }
}

nonisolated final class LegendTests: XCTestCase {
    @MainActor func testLegendCanScrollAndCloseToToday() throws {
        let app = try launchPlanAccount(presentLegend: true)
        defer { app.terminate() }
        app.scrollViews["legend.sheet"].swipeUp()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}

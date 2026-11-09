import XCTest

@MainActor func launchPlanAccount(presentLegend: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = AuthUIFlow.arguments()
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
    if presentLegend { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "legend" }
    app.launch()
    AuthUIFlow.openSignIn(app)
    AuthUIFlow.signIn(app, email: MockScenarioValues.demoEmail)
    if presentLegend {
        XCTAssertTrue(app.scrollViews["legend.sheet"].waitForExistence(timeout: 15))
    } else {
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["today.trip"].waitForExistence(timeout: 15))
    }
    return app
}

nonisolated final class TodayTests: XCTestCase {
    @MainActor func testTodayOpensTheTripRouteAndReturnsToItsRows() {
        let app = launchPlanAccount()
        defer { app.terminate() }
        let card = app.buttons["today.trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 12))
        card.tap()
        XCTAssertTrue(app.staticTexts["trip.destination"].waitForExistence(timeout: 4))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}

nonisolated final class StepSheetTests: XCTestCase {
    @MainActor func testTodayStepCanBeDoneUndoneSkippedAndReopened() {
        let app = launchPlanAccount()
        defer { app.terminate() }
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.step.actionable."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        AuthUIFlow.reveal(row, in: app, scroll: app.scrollViews["today.screen"])
        row.tap()
        let done = app.buttons["step.done"]
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
    }
}

nonisolated final class LegendTests: XCTestCase {
    @MainActor func testLegendCanScrollAndCloseToToday() {
        let app = launchPlanAccount(presentLegend: true)
        defer { app.terminate() }
        app.scrollViews["legend.sheet"].swipeUp()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}

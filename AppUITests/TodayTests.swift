import XCTest

@MainActor func launchPlanAccount(presentLegend: Bool = false, freezePlanClock: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = AuthUIFlow.arguments()
    app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
    app.launchEnvironment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
    if presentLegend { app.launchEnvironment["CF_PLAN_TEST_SHEET"] = "legend" }
    if freezePlanClock { app.launchEnvironment["CF_PLAN_TEST_FREEZE_CLOCK"] = "1" }
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
        XCTAssertTrue(app.scrollViews["trip.scroll"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForExistence(timeout: 12))
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
    @MainActor func testLegendCanScrollAndCloseToToday() {
        let app = launchPlanAccount(presentLegend: true)
        defer { app.terminate() }
        app.scrollViews["legend.sheet"].swipeUp()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }
}

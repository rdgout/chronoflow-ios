import XCTest

nonisolated final class RefreshTests: XCTestCase {
    @MainActor func testTodayAndMyTripsReportUpToDateOnlyAfterPull() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        XCTAssertFalse(app.staticTexts["refresh.feedback"].exists)
        pull(app.scrollViews["today.screen"])
        assertFeedback("Up to date", in: app)
        app.tabBars.buttons["My trips"].tap()
        pull(app.scrollViews["trips.screen"])
        assertFeedback("Up to date", in: app)
    }

    @MainActor func testEmptyTodayAndMyTripsCanRefresh() throws {
        let app = try launchPlanAccount(emptyTrips: true)
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 10))
        pull(app.scrollViews["today.screen"])
        assertFeedback("Up to date", in: app)
        app.tabBars.buttons["My trips"].tap()
        pull(app.scrollViews["trips.screen"])
        assertFeedback("Up to date", in: app)
    }

    @MainActor func testServerTripChangeIsReportedOnTodayAndMyTrips() throws {
        let app = try launchPlanAccount(updateTripOnRefresh: true)
        defer { app.terminate() }
        XCTAssertFalse(app.staticTexts["refresh.feedback"].exists)
        pull(app.scrollViews["today.screen"])
        assertFeedback("1 trip updated", in: app)
        app.tabBars.buttons["My trips"].tap()
        pull(app.scrollViews["trips.screen"])
        assertFeedback("1 trip updated", in: app)
    }

    @MainActor func testTripPageCanRefresh() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        app.buttons["today.trip"].tap()
        let scroll = app.scrollViews["trip.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForExistence(timeout: 12))
        AuthUIFlow.reveal(app.buttons["Legend: what the colours and patterns mean"], in: app, scroll: scroll)
        pull(scroll)
        assertFeedback("Up to date", in: app)
    }

    @MainActor private func pull(_ scroll: XCUIElement) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    @MainActor private func assertFeedback(_ text: String, in app: XCUIApplication) {
        let feedback = app.staticTexts["refresh.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertEqual(feedback.label, text)
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 5))
    }
}

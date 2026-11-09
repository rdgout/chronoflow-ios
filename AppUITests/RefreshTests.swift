import XCTest

nonisolated final class RefreshTests: XCTestCase {
    @MainActor func testTodayAndMyTripsReportUpToDateOnlyAfterPull() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["today.screen"], in: app)
        assertFeedback("Up to date", in: app)
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["trips.screen"], in: app)
        assertFeedback("Up to date", in: app)
    }

    @MainActor func testEmptyTodayAndMyTripsCanRefresh() throws {
        let app = try launchPlanAccount(emptyTrips: true)
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["today.screen"], in: app)
        assertFeedback("Up to date", in: app)
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["trips.screen"], in: app)
        assertFeedback("Up to date", in: app)
    }

    @MainActor func testServerTripChangeIsReportedOnTodayAndMyTrips() throws {
        let app = try launchPlanAccount(updateTripOnRefresh: true)
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["today.screen"], in: app)
        assertFeedback("1 trip updated", in: app)
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.scrollViews["trips.screen"], in: app)
        assertFeedback("1 trip updated", in: app)
    }

    @MainActor func testTripPageCanRefresh() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        app.buttons["today.trip"].tap()
        let scroll = app.scrollViews["trip.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["trip.viewToggle"].waitForExistence(timeout: 12))
        let legend = app.buttons["trip.legend"]
        for _ in 0..<12 {
            if legend.exists && legend.isHittable { break }
            scroll.swipeDown()
        }
        guard legend.waitForExistence(timeout: 4) else {
            XCTFail("Expected the trip summary legend after scrolling to the top: \(app.debugDescription)")
            return
        }
        AuthUIFlow.reveal(legend, in: app, scroll: scroll)
        pull(scroll, in: app)
        assertFeedback("Up to date", in: app)
    }

    @MainActor private func pull(_ scroll: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // Scroll-view frames extend under navigation and tab bars.
        let viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
        guard !viewport.isEmpty else {
            XCTFail("Expected visible content for \(scroll.identifier): \(app.debugDescription)")
            return
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.1))
        let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.9))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        attachScreenshot("\(scroll.identifier) immediately after pull")
    }

    @MainActor private func feedback(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "refresh.feedback").firstMatch
    }

    @MainActor private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func assertFeedback(_ text: String, in app: XCUIApplication) {
        let feedback = feedback(in: app)
        let appeared = feedback.waitForExistence(timeout: 12)
        let label = appeared ? feedback.label : nil
        attachScreenshot("Refresh feedback after wait: \(text)")
        guard appeared else {
            XCTFail("Expected refresh.feedback after pulling: \(app.debugDescription)")
            return
        }
        XCTAssertEqual(label, text)
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 5))
    }
}

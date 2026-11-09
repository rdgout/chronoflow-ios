import XCTest

nonisolated final class RefreshTests: XCTestCase {
    @MainActor func testTodayAndMyTripsReportUpToDateOnlyAfterPull() throws {
        let app = try launchPlanAccount()
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.buttons["today.trip"], in: app)
        try assertFeedback("Up to date", in: app, above: "today.trip")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.staticTexts["trips.section.active"], in: app)
        try assertFeedback("Up to date", in: app, above: "trips.section.active")
    }

    @MainActor func testEmptyTodayAndMyTripsCanRefresh() throws {
        let app = try launchPlanAccount(emptyTrips: true)
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.otherElements["today.empty"], in: app)
        try assertFeedback("Up to date", in: app, above: "today.empty")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.otherElements["trips.empty"], in: app)
        try assertFeedback("Up to date", in: app, above: "trips.empty")
    }

    @MainActor func testServerTripChangeIsReportedOnTodayAndMyTrips() throws {
        let app = try launchPlanAccount(updateTripOnRefresh: true)
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.buttons["today.trip"], in: app)
        try assertFeedback("1 trip updated", in: app, above: "today.trip")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        pull(app.staticTexts["trips.section.active"], in: app)
        try assertFeedback("1 trip updated", in: app, above: "trips.section.active")
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
        pull(app.staticTexts["Your plan"], in: app)
        try assertFeedback("Up to date", in: app, above: "Your plan")
    }

    @MainActor private func pull(_ content: XCUIElement, in app: XCUIApplication) {
        guard content.waitForExistence(timeout: 10), content.isHittable else {
            XCTFail("Expected visible first content \(content.identifier): \(app.debugDescription)")
            return
        }
        let start = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let end = start.withOffset(CGVector(dx: 0, dy: 350))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        attachScreenshot("\(content.identifier) immediately after pull")
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

    @MainActor private func assertFeedback(_ text: String, in app: XCUIApplication, above content: String) throws {
        let feedback = feedback(in: app)
        let appeared = feedback.waitForExistence(timeout: 12)
        guard appeared else {
            attachScreenshot("Refresh feedback after wait: \(text)")
            XCTFail("Expected refresh.feedback after pulling: \(app.debugDescription)")
            return
        }
        let elements = descendants(in: try app.snapshot())
        attachScreenshot("Refresh feedback after wait: \(text)")
        let matches = elements.filter { $0.identifier == "refresh.feedback" }
        let capsule = try XCTUnwrap(matches.first)
        let navigation = try XCTUnwrap(elements.first { $0.elementType == .navigationBar })
        let body = try XCTUnwrap(elements.first { $0.identifier == content || $0.label == content })
        XCTAssertEqual(capsule.label, text)
        XCTAssertEqual(matches.count, 1)
        XCTAssertGreaterThanOrEqual(capsule.frame.minY, navigation.frame.maxY)
        XCTAssertFalse(body.frame.isEmpty, "Expected content below refresh feedback")
        XCTAssertGreaterThanOrEqual(body.frame.minY, capsule.frame.maxY)
        XCTAssertTrue(feedback.waitForNonExistence(timeout: 5))
    }

    @MainActor private func descendants(in snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        [snapshot] + snapshot.children.flatMap { descendants(in: $0) }
    }
}

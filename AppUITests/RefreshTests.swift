import XCTest

nonisolated final class RefreshTests: XCTestCase {
    @MainActor func testTodayAndMyTripsReportUpToDateOnlyAfterPull() throws {
        let app = try launchPlanAccount(refreshCounter: true)
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        try pull(app.buttons["today.trip"], in: app, expecting: "Up to date", above: "today.trip")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        try pull(tripCard(in: app), in: app, expecting: "Up to date", above: "trips.section.active")
    }

    @MainActor func testEmptyTodayAndMyTripsCanRefresh() throws {
        let app = try launchPlanAccount(emptyTrips: true, refreshCounter: true)
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(feedback(in: app).exists)
        try pull(app.otherElements["today.empty"], in: app, expecting: "Up to date", above: "today.empty")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        try pull(app.otherElements["trips.empty"], in: app, expecting: "Up to date", above: "trips.empty")
    }

    @MainActor func testServerTripChangeIsReportedOnTodayAndMyTrips() throws {
        let app = try launchPlanAccount(updateTripOnRefresh: true, refreshCounter: true)
        defer { app.terminate() }
        XCTAssertFalse(feedback(in: app).exists)
        try pull(app.buttons["today.trip"], in: app, expecting: "1 trip updated", above: "today.trip")
        app.tabBars.buttons["My trips"].tap()
        XCTAssertFalse(feedback(in: app).exists)
        try pull(tripCard(in: app), in: app, expecting: "1 trip updated", above: "trips.section.active")
    }

    @MainActor func testTripPageCanRefresh() throws {
        let app = try launchPlanAccount(refreshCounter: true)
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
        try pull(app.otherElements["trip.summary"], in: app, expecting: "Up to date", above: "trip.summary")
    }

    @MainActor private func tripCard(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews["trips.screen"].buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "trip.")
        ).firstMatch
    }

    @MainActor private func pull(
        _ content: XCUIElement, in app: XCUIApplication, expecting text: String, above identifier: String
    ) throws {
        guard content.waitForExistence(timeout: 10), content.isHittable else {
            XCTFail("Expected visible first content \(content.identifier): \(app.debugDescription)")
            return
        }
        let counter = app.descendants(matching: .any).matching(identifier: "refresh.debug.count").firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5), "Expected the DEBUG refresh counter")
        let count = try XCTUnwrap(Int(counter.value as? String ?? ""))
        XCTAssertEqual(count, 0, "Automatic sync must not count as a user pull")
        let window = app.windows.firstMatch.frame
        let viewport = AuthScrollGesture.readingViewport(
            window, navigationBar: app.navigationBars.firstMatch.frame, tabBar: app.tabBars.firstMatch.frame,
            clearance: window.height * 0.02)
        let distance = window.height * 0.42
        let frame = content.frame.intersection(viewport)
        let point = CGPoint(x: frame.midX, y: min(frame.midY, viewport.maxY - distance))
        guard frame.contains(point), point.y >= viewport.minY + window.height * 0.04 else {
            XCTFail("Expected content well below navigation with room for a long pull: \(frame), \(viewport)")
            return
        }
        let start = content.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - content.frame.minX, dy: point.y - content.frame.minY))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        let snapshot = try app.snapshot()
        try assertFeedback(text, in: app, above: identifier, after: snapshot, expectedCount: count + 1)
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

    @MainActor private func assertFeedback(
        _ text: String, in app: XCUIApplication, above content: String,
        after snapshot: XCUIElementSnapshot, expectedCount: Int
    ) throws {
        let presented = app.descendants(matching: .any).matching(identifier: "refresh.debug.presented").firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: presented)
        let result = XCTWaiter.wait(for: [shown], timeout: 12)
        attachScreenshot("Refresh feedback after wait: \(text)")
        let elements = descendants(in: try app.snapshot())
        let count = Int(elements.first { $0.identifier == "refresh.debug.count" }?.value as? String ?? "")
        let outcome = elements.first { $0.identifier == "refresh.debug.outcome" }?.label ?? "missing"
        XCTAssertEqual(
            count, expectedCount, "Pull did not invoke native refresh (DEBUG count: \(String(describing: count)))")
        XCTAssertEqual(
            result, .completed,
            "Expected the \(text) capsule to render; presented: \(presented.label), outcome: \(outcome)")
        XCTAssertTrue(feedback(in: app).waitForNonExistence(timeout: 5), "Feedback must dismiss itself")
    }

    @MainActor private func descendants(in snapshot: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        [snapshot] + snapshot.children.flatMap { descendants(in: $0) }
    }
}

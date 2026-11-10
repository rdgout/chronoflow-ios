import XCTest

nonisolated final class RefreshTests: ScreenTestCase {
    @MainActor func testPullOnTodayShowsUpToDate() throws {
        let app = try launchPlanAccount(refreshCounter: true)
        try pull(app.buttons["today.trip"], in: app)
    }

    @MainActor func testTripPageCanRefresh() throws {
        let app = try launchPlanAccount(
            route: "trip:\(PlanUIFlow.tripID)", startAtSummary: true, refreshCounter: true)
        try pull(app.otherElements["trip.summary"], in: app)
    }

    @MainActor private func pull(_ content: XCUIElement, in app: XCUIApplication) throws {
        _ = try XCTUnwrap(content.waitUntil(.hittable, timeout: 4) ? content : nil, "Expected refreshable content")
        let window = app.windows.firstMatch.frame
        let viewport = AuthScrollGesture.readingViewport(
            window, navigationBar: app.navigationBars.firstMatch.frame, tabBar: app.tabBars.firstMatch.frame,
            clearance: window.height * 0.02)
        let distance = window.height * 0.42
        let frame = content.frame.intersection(viewport)
        let point = CGPoint(x: frame.midX, y: min(frame.midY, viewport.maxY - distance))
        guard frame.contains(point), point.y >= viewport.minY + window.height * 0.04 else {
            XCTFail("Expected content below navigation with room for a pull: \(frame), \(viewport)")
            return
        }
        let start = content.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: point.x - content.frame.minX, dy: point.y - content.frame.minY))
        let end = start.withOffset(CGVector(dx: 0, dy: distance))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        let presented = app.staticTexts["refresh.debug.presented"].firstMatch
        XCTAssertTrue(
            UIWait.until(timeout: 4) { presented.exists && presented.label == "Up to date" },
            "Expected the pull to render Up to date feedback")
    }
}

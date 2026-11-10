import XCTest

nonisolated final class RefreshTests: ScreenTestCase {
    @MainActor func testPullOnTodayShowsUpToDate() throws {
        let app = try launchPlanAccount()
        pull(app.buttons["today.trip"], in: app)
    }

    @MainActor func testTripPageCanRefresh() throws {
        let app = try launchPlanAccount(route: "trip:\(PlanUIFlow.tripID)", startAtSummary: true)
        pull(app.otherElements["trip.summary"], in: app)
    }

    @MainActor private func pull(_ content: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(content.waitUntil(.hittable, timeout: 4))
        let feedback = app.staticTexts["refresh.feedback"].firstMatch
        XCTAssertFalse(feedback.exists)
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
        XCTAssertTrue(UIWait.until(timeout: 4) { feedback.exists && feedback.label == "Up to date" })
        XCTAssertTrue(feedback.waitUntil(.gone, timeout: 4), "Feedback must dismiss itself")
    }
}

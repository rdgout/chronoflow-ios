import XCTest

nonisolated final class TimelinePerfTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    @MainActor func test60DayTimeToFirstTimelineFrame() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                TimelineBudgetMetric(
                    XCTOSSignpostMetric(
                        subsystem: "net.chronoflow.app.native", category: "Timeline",
                        name: "time-to-first-timeline-frame"), budget: .firstFrame),
                XCTApplicationLaunchMetric(),
            ], options: options
        ) {
            app.launch()
            waitForTimeline(app)
            app.terminate()
        }
    }

    @MainActor func test60DayScrollEndToEnd() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(
            metrics: [
                TimelineBudgetMetric(XCTOSSignpostMetric.scrollingAndDecelerationMetric, budget: .scrollingHitches),
                TimelineBudgetMetric(XCTMemoryMetric(application: app), budget: .memoryGrowth),
            ], options: options
        ) {
            app.launch()
            waitForTimeline(app)
            let scroll = app.scrollViews["trip.scroll"].firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            let menu = app.buttons["trip.dayMenu"]
            let initialDay = menu.value as? String
            XCTAssertFalse(initialDay?.isEmpty ?? true)
            // Resolve the scroll frame once; gutter gestures also avoid horizontal overflow lanes on small windows.
            let frame = scroll.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(
                CGVector(dx: frame.minX + frame.width * 0.08, dy: frame.minY + frame.height * 0.85))
            let finish = origin.withOffset(
                CGVector(dx: frame.minX + frame.width * 0.08, dy: frame.minY + frame.height * 0.15))
            startMeasuring()
            for _ in 0..<15 {
                start.press(forDuration: 0, thenDragTo: finish, withVelocity: .fast, thenHoldForDuration: 0)
            }
            stopMeasuring()
            let finalDay = menu.value as? String
            XCTAssertFalse(finalDay?.isEmpty ?? true)
            XCTAssertNotEqual(finalDay, initialDay, "Vertical swipes must advance beyond the opening day")
            print("Timeline scroll progress after 15 swipes: \(initialDay ?? "missing") -> \(finalDay ?? "missing")")
            app.terminate()
        }
    }

    @MainActor func test60DayLastDayReachesEnd() {
        let app = application()
        app.launch()
        defer { app.terminate() }
        waitForTimeline(app)
        let menu = app.buttons["trip.dayMenu"]
        menu.tap()
        let days = app.collectionViews.firstMatch
        XCTAssertTrue(days.waitForExistence(timeout: 5), "The native day menu must open its scrollable collection")
        // LargeTimelineFixtureTests pins this label to large60's final prepared day.
        let lastLabel = "Day 2.0 · Tue 8 Dec"
        let last = days.buttons.matching(NSPredicate(format: "label == %@", lastLabel)).firstMatch
        for _ in 0..<12 {
            if last.exists && last.isHittable { break }
            days.swipeUp(velocity: .fast)
        }
        guard last.exists && last.isHittable else {
            XCTFail("The native day menu must expose day 60 (\(lastLabel))")
            return
        }
        last.tap()
        let selection = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", lastLabel), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [selection], timeout: 10), .completed, "The day picker must select day 60")
        let scroll = app.scrollViews["trip.scroll"].firstMatch
        let end = app.descendants(matching: .any)["trip.plan.end"].firstMatch
        for _ in 0..<6 {
            if end.exists && end.isHittable { break }
            scroll.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(end.isHittable, "The end card must be reachable from day 60 in at most six swipes")
    }

    @MainActor private func waitForTimeline(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["trip.timeline.ready"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["trip.timeline.presented"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.trip-page", "large60", "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        return app
    }
}

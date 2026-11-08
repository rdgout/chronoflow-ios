import XCTest

nonisolated final class TimelinePerfTests: XCTestCase {
    @MainActor func test60DayTimeToFirstTimelineFrame() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTOSSignpostMetric(
                    subsystem: "net.chronoflow.app.native", category: "Timeline", name: "time-to-first-timeline-frame"),
                XCTApplicationLaunchMetric(),
            ], options: options
        ) {
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["trip.timeline.ready"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.descendants(matching: .any)["trip.timeline.presented"].firstMatch.waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor func test60DayScrollEndToEnd() {
        let app = application()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(
            metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTMemoryMetric(application: app)],
            options: options
        ) {
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)["trip.timeline.ready"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(
                app.descendants(matching: .any)["trip.timeline.presented"].firstMatch.waitForExistence(timeout: 10))
            let scroll = app.scrollViews["trip.scroll"].firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            let end = app.descendants(matching: .any)["trip.plan.end"].firstMatch
            startMeasuring()
            var swipes = 0
            while !(end.exists && end.isHittable) && swipes < 240 {
                scroll.swipeUp(velocity: .fast)
                swipes += 1
            }
            stopMeasuring()
            XCTAssertTrue(end.isHittable, "Did not traverse all 60 days after \(swipes) swipes")
            app.terminate()
        }
    }

    @MainActor private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.trip-page", "large60", "-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        return app
    }
}

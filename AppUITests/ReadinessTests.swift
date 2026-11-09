import XCTest

nonisolated final class ReadinessTests: XCTestCase {
    @MainActor
    func testSignedInReadyHandsOffToToday() {
        let app = launch(["-cf.session", "in", "-cf.stored", "yes"])
        XCTAssertTrue(app.tabBars.firstMatch.waitUntil(.exists, timeout: 12))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor
    func testSlowStatusAndHiddenRootUntilDelayedHandOff() {
        let app = launch(["-cf.session", "in", "-cf.stored", "no", "-cf.readyDelay", "3.5"])
        let opening = app.images["launch.opening"]
        XCTAssertTrue(UIWait.until(timeout: 5) { opening.value as? String == "Getting your plan ready" })
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitUntil(.exists, timeout: 5))
        XCTAssertFalse(opening.exists)
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launchMeasured()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }
}

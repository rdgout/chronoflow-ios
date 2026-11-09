import XCTest

nonisolated final class ReadinessTests: XCTestCase {
    @MainActor
    func testSignedInReadyHandsOffToToday() {
        let app = launch(["-cf.session", "in", "-cf.stored", "yes"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor
    func testSlowStatusAndHiddenRootUntilDelayedHandOff() {
        let app = launch(["-cf.session", "in", "-cf.stored", "no", "-cf.readyDelay", "3.5"])
        let opening = app.images["launch.opening"]
        let status = NSPredicate(format: "value == %@", "Getting your plan ready")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: status, object: opening)], timeout: 5), .completed
        )
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(opening.exists)
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["CF_AUTH_TEST_ID"] = UUID().uuidString
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }
}

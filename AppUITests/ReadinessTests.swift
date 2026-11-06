import XCTest

nonisolated final class ReadinessTests: XCTestCase {
    @MainActor
    func testSignedInReadyHandsOffToToday() {
        let app = launch(["-cf.session", "in", "-cf.stored", "yes"])
        XCTAssertTrue(app.staticTexts["route.today"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.images["launch.opening"].exists)
    }

    @MainActor
    func testSlowStatusAndHiddenRootUntilDelayedHandOff() {
        let start = Date()
        let app = launch(["-cf.session", "in", "-cf.stored", "no", "-cf.readyDelay", "3.5"])
        let opening = app.images["launch.opening"]
        let status = NSPredicate(format: "value == %@", "Getting your plan ready")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: status, object: opening)], timeout: 5), .completed
        )
        XCTAssertFalse(app.staticTexts["route.today"].exists)
        XCTAssertTrue(app.staticTexts["route.today"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 3.8)
        XCTAssertLessThan(Date().timeIntervalSince(start), 12)
        XCTAssertFalse(opening.exists)
    }

    @MainActor
    func testUnknownStoredDataHandsOffAtEightSecondsWithoutStatus() {
        let start = Date()
        let app = launch(["-cf.session", "in", "-cf.stored", "never"])
        let opening = app.images["launch.opening"]
        XCTAssertTrue(opening.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["route.today"].exists)
        XCTAssertNotEqual(opening.value as? String, "Getting your plan ready")
        XCTAssertTrue(app.staticTexts["route.today"].waitForExistence(timeout: 12))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 8.3)
        XCTAssertFalse(opening.exists)
    }

    @MainActor
    func testUnknownSessionDefaultsToWelcome() {
        let unknown = launch(["-cf.session", "never"])
        XCTAssertTrue(unknown.staticTexts["welcome.wordmark"].waitForExistence(timeout: 12))
        unknown.terminate()

    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }
}

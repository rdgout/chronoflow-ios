import XCTest

nonisolated final class WelcomeTests: XCTestCase {
    @MainActor
    func testFrozenMoonLandsOnTheMeasuredWelcomeMoon() throws {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-cf.mode", "welcome", "-cf.freezeAt", "2300",
                "-UIPreferredContentSizeCategoryName", category,
            ]
            app.launch()
            defer { app.terminate() }
            let opening = app.images["launch.opening"]
            XCTAssertTrue(opening.waitForExistence(timeout: 10))
            let hasMeasurement = NSPredicate { element, _ in
                (element as? XCUIElement)?.value is String
            }
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: hasMeasurement, object: opening)], timeout: 10),
                .completed)
            let value = try XCTUnwrap(opening.value as? String)
            let measurement = try JSONDecoder().decode([String: [Double]].self, from: Data(value.utf8))
            let target = try XCTUnwrap(measurement["target"])
            let moon = try XCTUnwrap(measurement["moon"])
            XCTAssertEqual(moon[0], target[0], accuracy: 0.5)
            XCTAssertEqual(moon[1], target[1], accuracy: 0.5)
            XCTAssertEqual(moon[2] * 104, target[2], accuracy: 0.5)
        }
    }
}

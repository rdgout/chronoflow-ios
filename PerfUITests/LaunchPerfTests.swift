import XCTest

nonisolated final class LaunchPerfTests: XCTestCase {
    @MainActor
    func testLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

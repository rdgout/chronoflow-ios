import XCTest

nonisolated final class UIWaitTests: XCTestCase {
    func testThreeConsecutiveSamplesIgnoreElapsedTimeAndResetOnChange() {
        var stability = FrameStability()
        let a = [CGRect(x: 1, y: 2, width: 3, height: 4)]
        XCTAssertFalse(stability.observe(a))
        XCTAssertFalse(stability.observe(a))
        XCTAssertTrue(stability.observe(a))
        XCTAssertFalse(stability.observe(nil))
        XCTAssertFalse(stability.observe(a))
        XCTAssertFalse(stability.observe(a))
        XCTAssertTrue(stability.observe(a))
    }

    func testFramesMustRepeatAfterEveryChangeOrMissingMeasurement() {
        var stability = FrameStability(requiredSamples: 2)
        let first = [CGRect(x: 10, y: 20, width: 30, height: 40)]
        let changed = [first[0].offsetBy(dx: 0, dy: 1)]
        XCTAssertFalse(stability.observe(first))
        XCTAssertTrue(stability.observe(first))
        XCTAssertFalse(stability.observe(changed))
        XCTAssertTrue(stability.observe(changed))
        for invalid in [nil, [], [CGRect.zero], [.null], [.infinite]] as [[CGRect]?] {
            XCTAssertFalse(stability.observe(invalid))
            XCTAssertFalse(stability.observe(changed))
            XCTAssertTrue(stability.observe(changed))
        }
        XCTAssertFalse(stability.observe(changed + first))
        XCTAssertTrue(stability.observe(changed + first))
    }
}

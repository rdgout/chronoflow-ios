import XCTest

nonisolated final class UIWaitTests: XCTestCase {
    func testSoftwareKeyboardMustHaveSubstantialVisibleAreaInsideTheWindow() {
        let window = CGRect(x: 0, y: 0, width: 466, height: 678)
        XCTAssertTrue(SoftwareKeyboardVisibility.isVisible(CGRect(x: 0, y: 400, width: 466, height: 278), in: window))
        XCTAssertTrue(SoftwareKeyboardVisibility.isVisible(CGRect(x: 0, y: 500, width: 466, height: 300), in: window))
        for keyboard in [
            CGRect(x: 0, y: 722, width: 466, height: 245),
            CGRect(x: 0, y: 678, width: 466, height: 245),
            CGRect(x: 0, y: 633, width: 466, height: 45),
            CGRect(x: 0, y: 677, width: 466, height: 245),
            CGRect(x: 465, y: 400, width: 466, height: 278),
            .zero, .null, .infinite,
        ] {
            XCTAssertFalse(SoftwareKeyboardVisibility.isVisible(keyboard, in: window), "\(keyboard)")
        }
        for invalidWindow in [CGRect.zero, .null, .infinite] {
            XCTAssertFalse(SoftwareKeyboardVisibility.isVisible(window, in: invalidWindow))
        }
    }

    func testSoftwareKeyboardVisibilityUsesWindowCoordinatesAndResetsStabilityWhileHidden() {
        let window = CGRect(x: 30, y: 50, width: 466, height: 678)
        let visible = CGRect(x: 30, y: 450, width: 466, height: 278)
        let hidden = CGRect(x: 30, y: 772, width: 466, height: 245)
        var stability = FrameStability()
        for keyboard in [visible, visible, hidden, visible, visible] {
            let frames = [window, keyboard]
            XCTAssertFalse(stability.observe(SoftwareKeyboardVisibility.isVisible(keyboard, in: window) ? frames : nil))
        }
        XCTAssertTrue(stability.observe([window, visible]))
    }

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

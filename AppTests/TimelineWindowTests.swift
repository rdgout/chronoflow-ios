import AppCore
import Launch
import UIKit
import XCTest

nonisolated final class TimelineWindowTests: XCTestCase {
    @MainActor
    func testOpeningAndMeasuredFallbackLandingOnTheRunningDevice() throws {
        let controller = UIViewController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 17, bottom: 8, right: 29)
        let host = try LaunchTestHost(controller: controller, style: .light)
        defer { host.close() }
        let size = host.window.bounds.size
        let safe = controller.view.safeAreaInsets
        let opening = LaunchTimeline.opening(size: size, reduceMotion: false)
        let path = FlightPath(size: size)
        XCTAssertEqual(path.start.y, size.height - 204)
        XCTAssertEqual(path.end.y, size.height - 204)
        for rowHeight: CGFloat in [28, 40, 96] {
            let target = MoonTarget.fallback(
                size: size,
                safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right),
                rowHeight: rowHeight)
            let timeline = opening.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: target)
            XCTAssertEqual(timeline.sample(at: .milliseconds(700)), opening.sample(at: .milliseconds(700)))
            let landed = timeline.sample(at: .milliseconds(2400))
            guard case .point(let position) = try XCTUnwrap(landed[.moon]?["position"]),
                case .scalar(let scale) = try XCTUnwrap(landed[.moon]?["transform.scale"])
            else { return XCTFail("Missing moon position or scale") }
            XCTAssertEqual(position.x, target.midX, accuracy: 0.01)
            XCTAssertEqual(position.y, target.midY, accuracy: 0.01)
            XCTAssertEqual(scale * 104, target.width, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(position.x - target.width / 2, safe.left)
            XCTAssertLessThanOrEqual(position.x + target.width / 2, size.width - safe.right)
            XCTAssertGreaterThanOrEqual(position.y - target.height / 2, safe.top)
            XCTAssertLessThanOrEqual(position.y + target.height / 2, size.height - safe.bottom)
        }
    }
}

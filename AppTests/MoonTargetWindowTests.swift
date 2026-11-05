import AppCore
import UIKit
import XCTest

nonisolated final class MoonTargetWindowTests: XCTestCase {
    @MainActor
    func testFallbackOnTheRunningDeviceWithAllFourSafeInsets() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let controller = UIViewController()
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 7, left: 19, bottom: 11, right: 31)
            let host = try LaunchTestHost(controller: controller, style: style)
            defer { host.close() }
            let size = host.window.bounds.size
            let safe = controller.view.safeAreaInsets
            let insets = MoonTarget.Insets(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right)
            let content = MoonTarget.contentBounds(size: size, safeAreaInsets: insets)
            XCTAssertEqual(content.minX, safe.left + 24)
            XCTAssertEqual(content.maxX, size.width - safe.right - 24)
            XCTAssertEqual(content.minY, max(safe.top + 16, 64))
            XCTAssertEqual(content.maxY, size.height - max(safe.bottom, 40))
            for rowHeight: CGFloat in [28, 40, 96] {
                let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: rowHeight)
                XCTAssertEqual(target.midX, safe.left + 38)
                XCTAssertEqual(target.midY, max(safe.top + 16, 64) + rowHeight / 2)
                XCTAssertTrue(content.contains(target))
            }
        }
    }
}

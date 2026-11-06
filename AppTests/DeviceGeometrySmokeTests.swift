import AppCore
import Launch
import UIKit
import XCTest

@testable import Welcome

nonisolated final class DeviceGeometrySmokeTests: XCTestCase {
    @MainActor func testLiveWindowMatchesPureLayouts() async throws {
        let host = WelcomeTestWindow(style: .light)
        defer { host.close() }
        try await host.layout()
        let size = host.window.bounds.size
        XCTAssertEqual(size, host.window.screen.bounds.size)
        let safe = host.controller.view.safeAreaInsets
        let insets = MoonTarget.Insets(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right)
        let layout = LaunchLayout(size: size, safeAreaInsets: insets)
        let launch = LaunchScene(size: size, traits: host.window.traitCollection, reduceMotion: false)
        XCTAssertEqual(launch.layer(.sun).position, layout.sunCentre)
        XCTAssertEqual(launch.layer(.wordmark).position, layout.wordmarkCentre)
        XCTAssertEqual(launch.layer(.status).frame, layout.status)
        let welcome = WelcomeGeometry(size: size, insets: insets)
        let brand = try XCTUnwrap(host.frames[.brand])
        XCTAssertEqual(brand.minX, welcome.content.minX, accuracy: 0.5)
        XCTAssertEqual(brand.minY, welcome.content.minY, accuracy: 0.5)
        try host.assertHorizontalInsets()
    }
}

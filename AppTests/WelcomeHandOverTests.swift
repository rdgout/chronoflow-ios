import AppCore
import DesignSystem
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class WelcomeHandOverTests: XCTestCase {
    @MainActor
    func testReconnectAndReduceMotionDoNotReplayTheIntro() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        defer {
            delegate.sceneDidDisconnect(scene)
            previous?.makeKey()
        }
        delegate.connect(
            to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.session", "out", "-cf.reduceMotion"]))
        for _ in 0..<100 where delegate.window == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(delegate.launchIntro)
        delegate.sceneDidDisconnect(scene)
        delegate.connect(to: scene, firstConnection: false, arguments: LaunchArguments(["-cf.session", "out"]))
        for _ in 0..<100 where delegate.window == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(delegate.launchIntro)
    }

    @MainActor
    func testRealWelcomePublishesAnAnchorToTheCoordinator() async throws {
        try await FontRegistry.register()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.session", "out"]))
        defer {
            delegate.sceneDidDisconnect(scene)
            previous?.makeKey()
        }
        for _ in 0..<100 where delegate.moonAnchorStore.frame == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let frame = try XCTUnwrap(delegate.moonAnchorStore.frame)
        XCTAssertEqual(delegate.coordinator?.state.moonTarget, frame)
        let launch = try XCTUnwrap(delegate.overlayController?.launchScene)
        launch.freeze(at: .milliseconds(2300))
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(50))
        let moon = try XCTUnwrap(launch.layer(.moon).presentation())
        XCTAssertEqual(moon.position.x, frame.midX, accuracy: 0.5)
        XCTAssertEqual(moon.position.y, frame.midY, accuracy: 0.5)
    }
}

import AppCore
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class LaunchConnectionTests: XCTestCase {
    @MainActor
    func testOpeningLabelIsAbsentDuringConstructionAndAvailableAfterCommit() throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let scene = LaunchScene(
            size: windowScene.coordinateSpace.bounds.size, traits: windowScene.traitCollection, reduceMotion: false)
        let controller = LaunchOverlayController(scene: scene)
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.view.accessibilityLabel)
        XCTAssertTrue(controller.view.isAccessibilityElement)
        scene.play(scene.timeline, at: CACurrentMediaTime())
        CATransaction.flush()
        controller.prepareAccessibilityLabel()
        XCTAssertFalse(controller.view.accessibilityLabel?.isEmpty ?? true)
    }

    @MainActor
    func testOverlayFlushPrecedesRootLayoutAndReconnectDoesNotReplay() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        var process = LaunchProcessState()
        let first = SceneDelegate()
        first.connect(to: scene, firstConnection: process.claimOverlay(), arguments: LaunchArguments([]))
        defer {
            first.overlayWindow?.isHidden = true
            first.window?.isHidden = true
            previousKey?.makeKey()
        }
        XCTAssertNil(first.window)
        XCTAssertEqual(first.signposts.events, [.sceneConnect, .overlayFirstCommit])
        let overlay = try XCTUnwrap(first.overlayWindow)
        XCTAssertEqual(overlay.windowLevel, .normal + 1)
        XCTAssertFalse(overlay.isHidden)
        let controller = try XCTUnwrap(first.overlayController)
        XCTAssertTrue(controller.view.accessibilityViewIsModal)
        XCTAssertTrue(controller.view.isAccessibilityElement)
        XCTAssertEqual(controller.view.accessibilityIdentifier, "launch.opening")
        XCTAssertFalse(controller.view.accessibilityLabel?.isEmpty ?? true)
        XCTAssertTrue(controller.view.accessibilityTraits.contains(.image))
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertGreaterThan(try XCTUnwrap(controller.launchScene.t0), 0)
        try await Task.sleep(for: .milliseconds(50))
        let window = try XCTUnwrap(first.window)
        window.layoutIfNeeded()
        let root = try XCTUnwrap(window.rootViewController)
        XCTAssertTrue(root.view.accessibilityElementsHidden)
        XCTAssertEqual(root.preferredStatusBarStyle, .lightContent)
        let events = first.signposts.events
        XCTAssertLessThan(
            try XCTUnwrap(events.firstIndex(of: .overlayFirstCommit)),
            try XCTUnwrap(events.firstIndex(of: .rootFirstLayout)))
        XCTAssertFalse(first.signposts.activeIntervals.contains(.firstCommit))
        let second = SceneDelegate()
        second.connect(to: scene, firstConnection: process.claimOverlay(), arguments: LaunchArguments([]))
        defer { second.window?.isHidden = true }
        XCTAssertNil(second.overlayWindow)
        XCTAssertNil(second.overlayController)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(try XCTUnwrap(second.window?.rootViewController?.view).accessibilityElementsHidden)
        XCTAssertEqual(second.window?.rootViewController?.preferredStatusBarStyle, .default)
    }
}

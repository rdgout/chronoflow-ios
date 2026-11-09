import AppCore
import DesignSystem
import Launch
import SwiftUI
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class WelcomeHandOverTests: XCTestCase {
    @MainActor
    func testFirstConnectionPlaysTheIntroAndReconnectShowsFinalWelcome() async throws {
        try await FontRegistry.register()
        XCTAssertFalse(
            UIAccessibility.isReduceMotionEnabled, "This regression requires a normal-motion first connection")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        defer {
            delegate.sceneDidDisconnect(scene)
            previous?.makeKey()
        }
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.session", "out"]))
        let first = try await waitForRoot(of: delegate)
        let intro = try XCTUnwrap(delegate.launchIntro)
        let exitStart = try XCTUnwrap(delegate.coordinator?.state.exitStart)
        XCTAssertEqual(intro.start, exitStart + .milliseconds(700))
        let root = try XCTUnwrap(first.rootViewController as? LaunchHostingController<RootView>)
        XCTAssertTrue(root.rootView.launchIntro === intro)
        try await waitUntil("Welcome did not claim its first-connection intro") { intro.hasPlayed }
        XCTAssertTrue(intro.hasPlayed)
        XCTAssertFalse(intro.claim(), "Welcome's first appearance must already have claimed the intro")
        delegate.sceneDidDisconnect(scene)
        XCTAssertNil(delegate.window)
        delegate.connect(to: scene, firstConnection: false, arguments: LaunchArguments(["-cf.session", "out"]))
        let remounted = try await waitForRoot(of: delegate)
        XCTAssertFalse(remounted === first)
        XCTAssertNil(delegate.launchIntro)
        XCTAssertNil(delegate.overlayWindow)
        XCTAssertNil(delegate.overlayController)
        XCTAssertEqual(delegate.navigator.route, .welcome)
        let remountedRoot = try XCTUnwrap(remounted.rootViewController as? LaunchHostingController<RootView>)
        XCTAssertNil(remountedRoot.rootView.launchIntro)
        XCTAssertFalse(remountedRoot.view.accessibilityElementsHidden)
        try await assertFinalWelcome(in: remounted, delegate: delegate, scene: scene)
    }

    @MainActor
    func testReduceMotionMountsWelcomeWithoutAnIntro() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        defer {
            delegate.sceneDidDisconnect(scene)
            previous?.makeKey()
        }
        delegate.connect(
            to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.session", "out", "-cf.reduceMotion"]))
        let window = try await waitForRoot(of: delegate)
        XCTAssertEqual(delegate.navigator.route, .welcome)
        XCTAssertNil(delegate.launchIntro)
        let root = try XCTUnwrap(window.rootViewController as? LaunchHostingController<RootView>)
        XCTAssertNil(root.rootView.launchIntro)
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

    @MainActor
    private func waitForRoot(of delegate: SceneDelegate) async throws -> UIWindow {
        try await waitUntil("Root window did not mount after font registration") { delegate.window != nil }
        let window = try XCTUnwrap(delegate.window)
        window.layoutIfNeeded()
        let root = try XCTUnwrap(window.rootViewController)
        root.view.layoutIfNeeded()
        XCTAssertTrue(root.view.window === window)
        XCTAssertFalse(window.isHidden)
        return window
    }

    @MainActor
    private func waitUntil(_ message: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "\(message)")
    }

    @MainActor
    private func assertFinalWelcome(in window: UIWindow, delegate: SceneDelegate, scene: UIWindowScene) async throws {
        try await waitUntil("Remounted Welcome did not lay out its measured moon") {
            delegate.moonAnchorStore.frame != nil
        }
        let referenceAnchor = MoonAnchorStore()
        let reference = UIWindow(windowScene: scene)
        let controller = LaunchHostingController(
            rootView: RootView(navigator: RootNavigator(route: .welcome), moonAnchorStore: referenceAnchor),
            signposts: LaunchSignposts())
        reference.frame = window.frame
        reference.maximumContentSizeCategory = window.maximumContentSizeCategory
        reference.overrideUserInterfaceStyle = window.traitCollection.userInterfaceStyle
        controller.traitOverrides.preferredContentSizeCategory = window.traitCollection.preferredContentSizeCategory
        controller.traitOverrides.displayScale = window.screen.scale
        reference.rootViewController = controller
        reference.makeKeyAndVisible()
        defer {
            reference.isHidden = true
            reference.rootViewController = nil
            window.makeKey()
        }
        reference.layoutIfNeeded()
        try await waitUntil("Final Welcome reference did not lay out its measured moon") {
            referenceAnchor.frame != nil
        }
        try await Task.sleep(for: .milliseconds(50))
        let expected = try capture(reference)
        let actual = try capture(window)
        XCTAssertTrue(
            WelcomeSnapshotPixels.hasVisibleVariation(actual), "Remounted Welcome must contain visible content")
        XCTAssertTrue(actual == expected, "Remounted Welcome must immediately match the final screen without an intro")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(try capture(window) == actual, "Remounted Welcome must stay final across intro animation time")
    }

    @MainActor
    private func capture(_ window: UIWindow) throws -> [UInt8] {
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = false
        format.preferredRange = .standard
        var rendered = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "Welcome hierarchy capture must succeed")
        return pixels(image)
    }
}

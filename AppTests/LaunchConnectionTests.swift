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
        first.connect(
            to: scene, firstConnection: process.claimOverlay(),
            arguments: LaunchArguments(["-cf.mode", "welcome", "-cf.freezeAt", "0"]))
        defer {
            first.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        XCTAssertNil(first.window)
        XCTAssertEqual(first.signposts.events, [.sceneConnect, .overlayFirstCommit])
        let overlay = try XCTUnwrap(first.overlayWindow)
        XCTAssertEqual(overlay.windowLevel, .normal + 1)
        XCTAssertEqual(overlay.overrideUserInterfaceStyle, scene.traitCollection.userInterfaceStyle)
        XCTAssertEqual(overlay.traitCollection.userInterfaceStyle, scene.traitCollection.userInterfaceStyle)
        XCTAssertFalse(overlay.isHidden)
        let controller = try XCTUnwrap(first.overlayController)
        XCTAssertTrue(controller.view.accessibilityViewIsModal)
        XCTAssertTrue(controller.view.isAccessibilityElement)
        XCTAssertEqual(controller.view.accessibilityIdentifier, "launch.opening")
        XCTAssertFalse(controller.view.accessibilityLabel?.isEmpty ?? true)
        XCTAssertTrue(controller.view.accessibilityTraits.contains(.image))
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertGreaterThan(try XCTUnwrap(controller.launchScene.t0), 0)
        let window = try await waitForRoot(of: first)
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
        second.connect(
            to: scene, firstConnection: process.claimOverlay(),
            arguments: LaunchArguments(["-cf.mode", "welcome", "-cf.freezeAt", "0"]))
        defer { second.sceneDidDisconnect(scene) }
        XCTAssertNil(second.overlayWindow)
        XCTAssertNil(second.overlayController)
        let secondWindow = try await waitForRoot(of: second)
        XCTAssertFalse(try XCTUnwrap(secondWindow.rootViewController?.view).accessibilityElementsHidden)
        XCTAssertEqual(second.window?.rootViewController?.preferredStatusBarStyle, .default)
    }

    @MainActor
    func testPerfServicesLoadOffMainAfterFlushAndDoNotConstructAccountServices() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        let loaded = expectation(description: "off-main service configuration")
        delegate.serviceConfigurationFactory = {
            XCTAssertFalse(Thread.isMainThread)
            loaded.fulfill()
            return (try AppServices(info: ["CHRONOFLOW_READINESS": "signed-out"], testing: true), nil)
        }
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments([]))
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        XCTAssertEqual(delegate.signposts.events, [.sceneConnect, .overlayFirstCommit])
        XCTAssertNotNil(delegate.overlayWindow)
        await fulfillment(of: [loaded], timeout: 5)
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.coordinator?.state.session == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(delegate.coordinator?.state.session, .signedOut)
        XCTAssertNil(delegate.nativeSession)
    }

    @MainActor
    func testLaunchDoesNotOverwriteSessionNavigation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        delegate.readinessFactory = { _, clock in
            StubReadiness(
                configuration: .init(session: .signedIn, stored: .never), store: KeychainSessionStore(), clock: clock)
        }
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments([]))
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.coordinator?.state.gate == nil, ContinuousClock.now < deadline { await Task.yield() }
        delegate.navigator.navigate(to: .signIn)
        delegate.coordinator?.send(.storedData(true))
        XCTAssertEqual(delegate.navigator.route, .signIn)
    }

    @MainActor
    private func waitForRoot(of delegate: SceneDelegate) async throws -> UIWindow {
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.window == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(delegate.window, "Root window did not mount after font registration")
    }
}

import AppCore
import DesignSystem
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class LaunchHandOffTests: XCTestCase {
    @MainActor
    func testRootWaitsForAResolvedRouteAndDisconnectCancelsReadiness() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let delegate = SceneDelegate()
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.session", "never"]))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(delegate.window)
        XCTAssertNil(delegate.navigator.route)
        XCTAssertNotNil(delegate.overlayWindow)
        delegate.sceneDidDisconnect(scene)
        XCTAssertNil(delegate.overlayWindow)
        XCTAssertNil(delegate.coordinator)
    }

    @MainActor
    func testTransactionCompletionIgnoresRepeatingDotsAndAnnouncesOnlyOnce() async throws {
        try await FontRegistry.register()
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let scene = LaunchScene(size: window.bounds.size, traits: windowScene.traitCollection, reduceMotion: false)
        var announcements: [NSAttributedString] = []
        let controller = LaunchOverlayController(scene: scene) { notification, argument in
            XCTAssertEqual(notification, .announcement)
            if let announcement = argument as? NSAttributedString { announcements.append(announcement) }
        }
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        scene.play(scene.timeline, at: CACurrentMediaTime() - 2)
        CATransaction.flush()
        controller.fontsDidRegister()
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        _ = reduce(&state, .reached(.seconds(2)), reduceMotion: false)
        let status = reduce(&state, .storedData(false), reduceMotion: false)
        controller.update(state: state, effects: status) {}
        let exit = reduce(&state, .gate(.terms), reduceMotion: false)
        let finished = expectation(description: "Exit opacity transaction completes")
        controller.update(state: state, effects: exit) { finished.fulfill() }
        controller.update(state: state, effects: []) {}
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(controller.statusAnnouncementCount, 1)
        XCTAssertEqual(announcements.count, 1)
        let announcement = try XCTUnwrap(announcements.first)
        XCTAssertEqual(announcement.string, "Getting your plan ready")
        XCTAssertEqual(
            announcement.attribute(.accessibilitySpeechQueueAnnouncement, at: 0, effectiveRange: nil) as? Bool, true)
        XCTAssertNotNil(scene.statusLine.text)
        XCTAssertEqual(scene.container.animationKeys()?.filter { $0 == "opacity" }.count, 1)
    }

    @MainActor
    func testCancellingScheduledStatusPreservesOpeningAndEpoch() throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let scene = LaunchScene(
            size: windowScene.coordinateSpace.bounds.size,
            traits: windowScene.traitCollection, reduceMotion: false)
        let controller = LaunchOverlayController(scene: scene)
        let t0 = CACurrentMediaTime()
        scene.play(scene.timeline, at: t0)
        let opening = scene.timeline.sample(at: .milliseconds(700))
        var state = LaunchState()
        _ = reduce(&state, .session(.signedIn(accountID: "a")), reduceMotion: false)
        let status = reduce(&state, .storedData(false), reduceMotion: false)
        controller.update(state: state, effects: status) {}
        let exit = reduce(&state, .gate(.terms), reduceMotion: false)
        controller.update(state: state, effects: exit) {}
        XCTAssertEqual(scene.timeline.sample(at: .milliseconds(700)), opening)
        XCTAssertNil(scene.statusLine.text)
        XCTAssertEqual(controller.statusAnnouncementCount, 0)
        for layer in scene.layers.values {
            for key in layer.animationKeys() ?? [] {
                XCTAssertEqual(layer.animation(forKey: key)?.beginTime, t0)
            }
        }
    }

    @MainActor
    func testAnchorRebuildOnlyCompletesTheLatestExitTransaction() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: windowScene)
        let scene = LaunchScene(size: window.bounds.size, traits: windowScene.traitCollection, reduceMotion: false)
        let controller = LaunchOverlayController(scene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        scene.play(scene.timeline, at: CACurrentMediaTime() - 1.4)
        CATransaction.flush()
        let safe = controller.view.safeAreaInsets
        let first = MoonTarget.fallback(
            size: window.bounds.size,
            safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right), rowHeight: 28
        )
        var state = LaunchState(fallbackTarget: first)
        _ = reduce(&state, .session(.signedOut), reduceMotion: false)
        let firstExit = reduce(&state, .moonAnchor(first), reduceMotion: false)
        var staleCompletions = 0
        controller.update(state: state, effects: firstExit) { staleCompletions += 1 }
        let measured = first.offsetBy(dx: 2, dy: 2)
        let replacement = reduce(&state, .moonAnchor(measured), reduceMotion: false)
        let finished = expectation(description: "Latest anchor exit completes")
        controller.update(state: state, effects: replacement) { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(staleCompletions, 0)
        XCTAssertEqual(scene.container.animationKeys()?.filter { $0 == "opacity" }.count, 1)
    }

    @MainActor
    func testRealCoordinatorReleasesOverlayAndRestoresRootAccessibilityAndStatusBar() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        autoreleasepool {
            delegate.connect(
                to: scene, firstConnection: true,
                arguments: LaunchArguments(["-cf.session", "in", "-cf.stored", "yes"]))
        }
        weak let overlay = delegate.overlayWindow
        weak let overlayController = delegate.overlayController
        defer {
            delegate.sceneDidDisconnect(scene)
            delegate.overlayWindow?.isHidden = true
            delegate.window?.isHidden = true
            previousKey?.makeKey()
        }
        for _ in 0..<100 where delegate.window == nil { try await Task.sleep(for: .milliseconds(10)) }
        let root = try XCTUnwrap(delegate.window?.rootViewController)
        XCTAssertTrue(root.view.accessibilityElementsHidden)
        XCTAssertEqual(delegate.navigator.route, .today)
        XCTAssertEqual(root.preferredStatusBarStyle, .lightContent)
        for _ in 0..<300 where delegate.overlayWindow != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(delegate.overlayWindow)
        XCTAssertNil(delegate.overlayController)
        try await drainUntilReleased { overlay == nil && overlayController == nil }
        XCTAssertNil(overlay)
        XCTAssertNil(overlayController)
        XCTAssertFalse(root.view.accessibilityElementsHidden)
        XCTAssertEqual(root.preferredStatusBarStyle, .default)
        XCTAssertEqual(delegate.signposts.events.filter { $0 == .overlayRemoved }.count, 1)
        XCTAssertFalse(delegate.signposts.activeIntervals.contains(.launch))
        XCTAssertFalse(delegate.signposts.activeIntervals.contains(.exit))
        XCTAssertEqual(delegate.coordinator?.state.exitStart?.components.seconds, 1)
        XCTAssertTrue(delegate.coordinator?.state.isComplete == true)
    }

    @MainActor
    func testDisconnectReleasesTheOverlayWhileItsExitIsPending() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        autoreleasepool {
            delegate.connect(
                to: scene, firstConnection: true,
                arguments: LaunchArguments(["-cf.session", "in", "-cf.stored", "yes"]))
        }
        weak let overlay = delegate.overlayWindow
        weak let controller = delegate.overlayController
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        for _ in 0..<100 where delegate.coordinator?.state.didCommitExit != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(delegate.coordinator?.state.didCommitExit == true)
        autoreleasepool { delegate.sceneDidDisconnect(scene) }
        XCTAssertNil(delegate.overlayWindow)
        XCTAssertNil(delegate.overlayController)
        XCTAssertNil(delegate.coordinator)
        try await drainUntilReleased { overlay == nil && controller == nil }
        XCTAssertNil(overlay)
        XCTAssertNil(controller)
        XCTAssertEqual(delegate.signposts.events.filter { $0 == .overlayRemoved }.count, 1)
        XCTAssertNil(delegate.window)
    }

    @MainActor
    private func drainUntilReleased(_ released: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !autoreleasepool(invoking: released) && ContinuousClock.now < deadline {
            drainRunLoop()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private func drainRunLoop() {
        // UIKit can defer releasing hidden windows and detached controllers until its next transaction.
        autoreleasepool {
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

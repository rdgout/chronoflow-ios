import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class SyncLifecycleTests: XCTestCase {
    @MainActor
    func testSceneForwardsActivationBackgroundAndDisconnectWithoutReplayingOverlay() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let delegate = SceneDelegate()
        delegate.connect(to: scene, firstConnection: false, arguments: LaunchArguments(["-cf.mode", "ready"]))
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        var activity: [Bool] = []
        delegate.sessionActivity = { activity.append($0) }
        delegate.sceneDidBecomeActive(scene)
        delegate.sceneDidEnterBackground(scene)
        delegate.sceneDidBecomeActive(scene)
        delegate.sceneDidDisconnect(scene)
        XCTAssertEqual(activity, [true, false, true, false])
        XCTAssertNil(delegate.overlayWindow)
    }
}

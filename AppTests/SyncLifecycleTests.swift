import AppCore
import Foundation
import Sync
import UIKit
import XCTest

@testable import ChronoFlow

private actor SceneSyncProbe {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

private actor SceneSyncPath: SyncPathMonitoring {
    let probe: SceneSyncProbe
    private var continuation: AsyncStream<Bool>.Continuation?
    init(probe: SceneSyncProbe) { self.probe = probe }
    func updates() async -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.continuation = continuation
        await probe.record("path.start")
        return stream
    }
    func stop() async {
        continuation?.finish()
        continuation = nil
        await probe.record("path.stop")
    }
}

private actor SceneSyncClock {
    private var timers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    var pending: Int { timers.count }
    func sleep(_ seconds: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { timers[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        try Task.checkCancellation()
    }
    private func cancel(_ id: UUID) { timers.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

private actor SceneSyncCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

nonisolated final class SyncLifecycleTests: XCTestCase {
    @MainActor
    func testSceneControlsNativeSyncAndReconnectResumesExistingSessionWithoutOverlay() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scene-sync-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = SceneSyncProbe()
        let clock = SceneSyncClock()
        let services = try AppServices(testing: true)
        let credentials = SceneSyncCredentials()
        let id = "019a562b-8000-7000-8000-000000000001"
        await credentials.write(try JSONEncoder().encode(StoredSession(token: "test-token", accountId: id)))
        let native = NativeSessionController(
            applicationSupport: root, namespace: .mock, credentials: credentials,
            syncScheduler: SyncScheduler(sleep: { try await clock.sleep($0) }),
            syncPath: { SceneSyncPath(probe: probe) },
            source: { session in
                await probe.record("source")
                return services.makeDataSource(applicationSupport: root, session: session)
            })
        let delegate = SceneDelegate()
        delegate.serviceConfigurationFactory = { (services, root) }
        delegate.nativeSessionFactory = { _, _ in native }
        delegate.connect(to: scene, firstConnection: true, arguments: LaunchArguments([]))
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        let opened = await Self.eventually {
            let events = await probe.events
            let pending = await clock.pending
            return events == ["source", "path.start"] && pending == 1
        }
        XCTAssertTrue(opened)
        XCTAssertTrue(delegate.nativeSession === native)
        let epoch = await native.controller.epoch
        delegate.sceneDidBecomeActive(scene)
        delegate.sceneDidEnterBackground(scene)
        let paused = await Self.eventually {
            let events = await probe.events
            let pending = await clock.pending
            return events == ["source", "path.start", "path.stop"] && pending == 0
        }
        XCTAssertTrue(paused)
        delegate.sceneDidBecomeActive(scene)
        let resumed = await Self.eventually {
            let events = await probe.events
            let pending = await clock.pending
            return events == ["source", "path.start", "path.stop", "source", "path.start"] && pending == 1
        }
        XCTAssertTrue(resumed)
        delegate.navigator.navigate(to: .today)
        delegate.sceneDidDisconnect(scene)
        let disconnected = await Self.eventually {
            let events = await probe.events
            let pending = await clock.pending
            return events == ["source", "path.start", "path.stop", "source", "path.start", "path.stop"]
                && pending == 0
        }
        XCTAssertTrue(disconnected)
        delegate.connect(to: scene, firstConnection: false, arguments: LaunchArguments([]))
        delegate.sceneDidBecomeActive(scene)
        let reconnected = await Self.eventually {
            let events = await probe.events
            let pending = await clock.pending
            return events == [
                "source", "path.start", "path.stop", "source", "path.start", "path.stop", "source", "path.start",
            ] && pending == 1
        }
        XCTAssertTrue(reconnected)
        XCTAssertNil(delegate.overlayWindow)
        XCTAssertEqual(delegate.navigator.route, .today)
        XCTAssertEqual(delegate.signposts.events.filter { $0 == .overlayFirstCommit }.count, 1)
        let resumedEpoch = await native.controller.epoch
        XCTAssertEqual(resumedEpoch, epoch)
        delegate.sceneDidDisconnect(scene)
        let drained = await Self.eventually { await clock.pending == 0 }
        XCTAssertTrue(drained)
        await native.sync?.stop()
        await native.stopObserving()
        try await native.accounts.close()
    }

    nonisolated private static func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }
}

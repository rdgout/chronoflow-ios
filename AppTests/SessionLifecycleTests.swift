import AppCore
import Foundation
import LocalStore
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated private func lifecycleIsMainThread() -> Bool { Thread.isMainThread }

private actor SuspendedSessionAccounts: SessionAccountStore {
    let entered: XCTestExpectation
    let database: SessionAccountDatabase
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(entered: XCTestExpectation, database: SessionAccountDatabase) {
        self.entered = entered
        self.database = database
    }

    func open(accountID: AccountID) async throws {
        XCTAssertFalse(lifecycleIsMainThread())
        entered.fulfill()
        if !released { await withCheckedContinuation { continuation = $0 } }
        try await database.open(accountID: accountID)
    }
    func upsert(_ account: SessionAccount) async throws { try await database.upsert(account) }
    func close() async throws { try await database.close() }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor LifecycleSessionStore: SessionStore {
    let data: Data
    init(data: Data) { self.data = data }
    func read() -> Data? {
        XCTAssertFalse(lifecycleIsMainThread())
        return data
    }
    func write(_ data: Data) {}
    func delete() {}
}

nonisolated final class SessionLifecycleTests: XCTestCase {
    @MainActor
    func testNativeFirstFlushAndSuspendedOpenUseProductionStoredDataReadiness() async throws {
        for fixture in [
            (verified: true, cached: true, gate: Gate.app, stored: true),
            (verified: true, cached: false, gate: Gate.app, stored: false),
            (verified: false, cached: false, gate: Gate.verify, stored: false),
        ] {
            try await assertNativeLaunch(
                verified: fixture.verified, cached: fixture.cached,
                expectedGate: fixture.gate, expectedStored: fixture.stored)
        }
    }

    @MainActor
    private func assertNativeLaunch(
        verified: Bool, cached: Bool, expectedGate: Gate, expectedStored: Bool
    ) async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = windowScene.windows.first(where: \.isKeyWindow)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-launch-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = "019a562b-8000-7000-8000-000000000001"
        let fixtureStore = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        try await fixtureStore.open(accountID: AccountID(id))
        try await fixtureStore.upsert(
            SessionAccount(
                id: id, name: "Test", email: "test@example.test", hasVerifiedEmail: verified,
                policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
                walkthroughSeen: true))
        if cached, let database = await fixtureStore.activeDatabase() {
            try await AccountRepository(database: database).upsert(
                AccountRecord(
                    id: id, name: "Test", email: "test@example.test", hasVerifiedEmail: verified,
                    syncedAt: "2026-11-06T00:00:00Z", walkthroughSeen: true))
        }
        try await fixtureStore.close()
        let entered = expectation(description: "native off-main open suspended")
        let configured = expectation(description: "native services configured after flush")
        let data = try JSONEncoder().encode(StoredSession(token: "test", accountId: id))
        let delegate = SceneDelegate()
        var suspended: SuspendedSessionAccounts?
        var native: NativeSessionController?
        delegate.serviceConfigurationFactory = { [signposts = delegate.signposts] in
            XCTAssertFalse(lifecycleIsMainThread())
            await MainActor.run {
                XCTAssertEqual(signposts.events, [.sceneConnect, .overlayFirstCommit])
            }
            configured.fulfill()
            return (try AppServices(info: ["CHRONOFLOW_READINESS": "native"], testing: true), root)
        }
        delegate.nativeSessionFactory = { [weak delegate] services, loadedRoot in
            XCTAssertEqual(delegate?.signposts.events, [.sceneConnect, .overlayFirstCommit])
            XCTAssertEqual(loadedRoot, root)
            let result = NativeSessionController(
                applicationSupport: loadedRoot, namespace: services.namespace,
                credentials: LifecycleSessionStore(data: data),
                accountStore: { database in
                    let store = SuspendedSessionAccounts(entered: entered, database: database)
                    suspended = store
                    return store
                })
            native = result
            return result
        }
        delegate.connect(to: windowScene, firstConnection: true, arguments: LaunchArguments([]))
        defer {
            delegate.sceneDidDisconnect(windowScene)
            previousKey?.makeKey()
        }
        XCTAssertEqual(delegate.signposts.events, [.sceneConnect, .overlayFirstCommit])
        await fulfillment(of: [configured, entered], timeout: 5)
        XCTAssertTrue(delegate.coordinator?.readiness is StoredDataReadiness)
        XCTAssertTrue(delegate.nativeSession === native)
        let overlay = try XCTUnwrap(delegate.overlayWindow)
        let launchScene = try XCTUnwrap(delegate.overlayController?.launchScene)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertNil(delegate.coordinator?.state.session)
        XCTAssertNil(delegate.window)
        XCTAssertNotNil(launchScene.t0)
        let animationKeys = launchScene.container.sublayers?.flatMap { $0.animationKeys() ?? [] } ?? []
        if !launchScene.timeline.reduceMotion { XCTAssertFalse(animationKeys.isEmpty) }
        let heartbeat = expectation(description: "main actor remains responsive during native open")
        Task { @MainActor in heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 1)
        XCTAssertTrue(delegate.overlayWindow === overlay)
        XCTAssertFalse(overlay.isHidden)
        let store = try XCTUnwrap(suspended)
        await store.release()
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.coordinator?.state.gate == nil || delegate.coordinator?.state.hasStoredData == nil,
            ContinuousClock.now < deadline
        { await Task.yield() }
        XCTAssertEqual(delegate.coordinator?.state.session, .signedIn(accountID: id))
        XCTAssertEqual(delegate.coordinator?.state.gate, expectedGate)
        XCTAssertEqual(delegate.coordinator?.state.hasStoredData, expectedStored)
        delegate.sceneDidDisconnect(windowScene)
        await native?.stopObserving()
        try await native?.accounts.close()
    }
    @MainActor
    func testNativeCompositionObservesAndDetachesAccountsUsingOneKeychainStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "session-lifecycle-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = KeychainSessionStore(service: "net.chronoflow.tests.lifecycle." + UUID().uuidString)
        let native = NativeSessionController(applicationSupport: root, namespace: .mock, credentials: credentials)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(native.model.state, .unknown)
        native.observe()
        do {
            var firstDatabase: AccountDatabase?
            for id in ["019a562b-8000-7000-8000-000000000001", "019a562b-8000-7000-8000-000000000002"] {
                let account = SessionAccount(
                    id: id, name: "Test", email: "test@example.test", hasVerifiedEmail: true,
                    policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"), walkthroughSeen: false)
                try await native.controller.accept(SessionResult(token: "test-token", account: account))
                let deadline = ContinuousClock.now + .seconds(5)
                while ContinuousClock.now < deadline {
                    if case .loaded(let value) = native.model.state, value?.id == id { break }
                    await Task.yield()
                }
                guard case .loaded(let value) = native.model.state else {
                    XCTFail("Native account observation did not load")
                    break
                }
                XCTAssertEqual(value?.id, id)
                XCTAssertNil(value?.syncedAt)
                let stored = try await credentials.readStoredSession()
                XCTAssertEqual(stored?.accountId, id)
                if firstDatabase == nil { firstDatabase = await native.accounts.activeDatabase() }
            }
            if let firstDatabase {
                do {
                    _ = try await AccountRepository(database: firstDatabase).account()
                    XCTFail("The first account database remained open")
                } catch { XCTAssertEqual(error as? StoreFailure, .closed) }
            }
            await native.stopObserving()
            XCTAssertEqual(native.model.state, .unknown)
            try await native.accounts.close()
            try await credentials.delete()
        } catch {
            await native.stopObserving()
            try? await native.accounts.close()
            try? await credentials.delete()
            throw error
        }
    }

}

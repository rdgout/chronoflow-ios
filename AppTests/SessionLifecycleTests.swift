import AppCore
import Foundation
import LocalStore
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated private func lifecycleIsMainThread() -> Bool { Thread.isMainThread }

private actor SuspendedSessionAccounts: SessionAccountStore {
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(entered: XCTestExpectation) { self.entered = entered }

    func open(accountID: AccountID) async {
        XCTAssertFalse(lifecycleIsMainThread())
        entered.fulfill()
        if !released { await withCheckedContinuation { continuation = $0 } }
    }
    func upsert(_ account: SessionAccount) {}
    func close() {}
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

private actor ControllerReadiness: LaunchReadiness {
    let controller: SessionController
    init(_ controller: SessionController) { self.controller = controller }
    func session() async -> SessionPresence { (try? await controller.restore()) ?? .signedOut }
    func gate() -> Gate { .app }
    func hasStoredData() -> Bool { false }
    func allowFirstLoad() {}
}

nonisolated final class SessionLifecycleTests: XCTestCase {
    @MainActor
    func testFirstFlushPrecedesServiceConstructionAndSuspendedOpenDoesNotBlockMainActor() async throws {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = windowScene.windows.first(where: \.isKeyWindow)
        let entered = expectation(description: "off-main database open started")
        let accounts = SuspendedSessionAccounts(entered: entered)
        let data = try JSONEncoder().encode(
            StoredSession(token: "test", accountId: "019a562b-8000-7000-8000-000000000001"))
        let delegate = SceneDelegate()
        var constructed = false
        delegate.readinessFactory = { [weak delegate] _, _ in
            XCTAssertEqual(delegate?.signposts.events, [.sceneConnect, .overlayFirstCommit])
            XCTAssertNotNil(delegate?.overlayWindow)
            constructed = true
            return ControllerReadiness(
                SessionController(credentials: LifecycleSessionStore(data: data), accounts: accounts))
        }
        delegate.connect(to: windowScene, firstConnection: true, arguments: LaunchArguments([]))
        defer {
            delegate.sceneDidDisconnect(windowScene)
            previousKey?.makeKey()
        }
        XCTAssertTrue(constructed)
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertNotNil(delegate.overlayController)
        XCTAssertNil(delegate.window)
        XCTAssertNil(delegate.coordinator?.state.session)
        await Task.yield()
        XCTAssertNotNil(delegate.overlayWindow)
        await accounts.release()
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.coordinator?.state.session == nil, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(
            delegate.coordinator?.state.session, .signedIn(accountID: "019a562b-8000-7000-8000-000000000001"))
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

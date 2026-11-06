import AppCore
import Auth
import DataAccess
import Foundation
import LocalStore
import XCTest

@testable import ChronoFlow

nonisolated final class SessionReadinessTests: XCTestCase {
    @MainActor
    func testAuthReusesNativeSessionAndStoredGateThroughRestoreAndSignOut() async throws {
        for (verified, accepted, seen, expected) in [
            (false, false, false, Route.verify), (true, false, false, .terms),
            (true, true, false, .walkthrough), (true, true, true, .today),
        ] {
            for usePasskey in [false, true] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "auth-session-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: root) }
                let credentials = AuthMemoryCredentials()
                let probe = AuthSyncProbe()
                let app = AppDelegate()
                let native = NativeSessionController(
                    applicationSupport: root, namespace: .mock, credentials: credentials,
                    requestSync: { await probe.request($0) },
                    signedOut: { app.navigator.navigate(to: .signIn) })
                app.nativeSession = native
                let fixture = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "Packages/ChronoFlowKit/Tests/DataAccessTests/Fixtures/account/snapshot.json")
                var snapshot = try JSONDecoder().decode(AccountSnapshot.self, from: Data(contentsOf: fixture))
                snapshot.hasVerifiedEmail = verified
                snapshot.settings.policies = AccountPolicies(
                    termsVersion: "2", privacyVersion: "2", acceptedTermsVersion: accepted ? "2" : "1")
                let accountID = snapshot.id
                let server = MockServerAccount(
                    snapshot: snapshot, password: "Password123!", twoFactorCode: usePasskey ? "123456" : nil,
                    walkthroughSeen: seen)
                let auth = AuthSessionServices(
                    services: try AppServices(info: ["CHRONOFLOW_DATA_SOURCE": "mock"], testing: true),
                    applicationSupport: root, nativeSession: native, navigator: app.navigator,
                    source: MockDataSource(
                        seed: MockServerState(accounts: [server]), delay: { 0 }, sleep: { _ in },
                        assertionProvider: { credential, _ in credential.id == "AQ" ? accountID : nil }),
                    assertionProvider: DeterministicAssertionProvider { _ in
                        Base64URL.assertion(
                            credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                            signature: Data([4]), userHandle: nil)
                    },
                    verification: { epoch in await app.verificationRequired(epoch: epoch) })
                XCTAssertTrue(auth.nativeSession === native)
                auth.model.editEmail(snapshot.email)
                auth.model.editPassword("Password123!")
                if usePasskey { await auth.model.submitPasskey() } else { await auth.model.submitPassword() }
                XCTAssertNil(auth.model.sessionFailure)
                XCTAssertEqual(app.navigator.route, expected)
                let current = await native.controller.activeSession()
                XCTAssertEqual(current?.session.accountId, snapshot.id)
                let requests = await probe.epochs
                XCTAssertEqual(requests, [current?.epoch].compactMap { $0 })
                let restored = try await native.controller.restore()
                XCTAssertEqual(restored, .signedIn(accountID: snapshot.id))
                await native.routeAcceptedSession(navigator: app.navigator) { epoch in
                    await app.verificationRequired(epoch: epoch)
                }
                XCTAssertEqual(app.navigator.route, expected)
                let staleEpoch = await native.controller.epoch
                _ = try await native.controller.signOut(discardPending: true, unauthorized: true)
                XCTAssertEqual(app.navigator.route, .signIn)
                await app.verificationRequired(epoch: staleEpoch)
                XCTAssertEqual(app.navigator.route, .signIn)
                let stored = try await credentials.readStoredSession()
                let database = await native.accounts.activeDatabase()
                XCTAssertNil(stored)
                XCTAssertNil(database)
                await native.stopObserving()
            }
        }
    }

    @MainActor
    func testKeychainRestoreUsesSQLiteMarkerAndObservesFirstSuccessfulPull() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = KeychainSessionStore(service: "net.chronoflow.tests.readiness." + UUID().uuidString)
        let native = NativeSessionController(applicationSupport: root, namespace: .mock, credentials: credentials)
        let id = "019a562b-8000-7000-8000-000000000001"
        let account = SessionAccount(
            id: id, name: "Test", email: "a@example.test", hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
            walkthroughSeen: true)
        try await native.controller.accept(SessionResult(token: "test-token", account: account))
        let source = native.readiness
        let restored = await source.session()
        XCTAssertEqual(restored, .signedIn(accountID: id))
        let gate = await source.gate()
        XCTAssertEqual(gate, .app)
        let values = await source.storedDataUpdates()
        defer { withExtendedLifetime(values) {} }
        var stream = values.makeAsyncIterator()
        let initial = await stream.next()
        XCTAssertEqual(initial, false)
        let active = await native.accounts.activeDatabase()
        let database = try XCTUnwrap(active)
        try await AccountRepository(database: database).upsert(
            AccountRecord(
                id: id, name: "Test", email: "a@example.test", syncedAt: "2026-11-06T00:00:00Z", walkthroughSeen: true))
        let ready = await stream.next()
        XCTAssertEqual(ready, true)
        _ = try await native.controller.signOut(discardPending: true, unauthorized: true)
        await native.stopObserving()
    }
    @MainActor
    func testClosedAccountCannotSilentlyDiscardPendingChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("closed-outbox-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = KeychainSessionStore(service: "net.chronoflow.tests.closed." + UUID().uuidString)
        let native = NativeSessionController(applicationSupport: root, namespace: .mock, credentials: credentials)
        let id = "019a562b-8000-7000-8000-000000000001"
        let account = SessionAccount(
            id: id, name: "Test", email: "a@example.test", hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"), walkthroughSeen: false)
        try await native.controller.accept(SessionResult(token: "test-token", account: account))
        let active = await native.accounts.activeDatabase()
        let database = try XCTUnwrap(active)
        _ = try await OutboxRepository(database: database).enqueue(.walkthrough)
        try await native.accounts.close()
        // A new controller with credentials but no restored account also takes the closed-store path.
        let unrestored = NativeSessionController(applicationSupport: root, namespace: .mock, credentials: credentials)
        do {
            _ = try await unrestored.controller.signOut(discardPending: false)
            XCTFail("An unknown pending count must prevent voluntary deletion")
        } catch { XCTAssertEqual(error as? StoreFailure, .closed) }
        let stored = try await credentials.readStoredSession()
        XCTAssertEqual(stored?.accountId, id)
        try await native.accounts.open(accountID: AccountID(id))
        let reopenedActive = await native.accounts.activeDatabase()
        let reopened = try XCTUnwrap(reopenedActive)
        let pending = try await OutboxRepository(database: reopened).pending()
        XCTAssertEqual(pending.count, 1)
        try await native.accounts.close()
        _ = try await unrestored.controller.signOut(discardPending: true)
    }

}

private actor AuthMemoryCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor AuthSyncProbe {
    private(set) var epochs: [UInt64] = []
    func request(_ epoch: UInt64) { epochs.append(epoch) }
}

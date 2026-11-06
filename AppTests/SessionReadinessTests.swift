import AppCore
import Foundation
import LocalStore
import XCTest

@testable import ChronoFlow

nonisolated final class SessionReadinessTests: XCTestCase {
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

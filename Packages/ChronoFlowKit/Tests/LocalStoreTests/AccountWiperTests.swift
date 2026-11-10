import AppCore
import Foundation
import Testing

@testable import LocalStore

private actor WipeCredentials: SessionStore {
    var data: Data? = Data("test-session".utf8)
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private final class FailingRemoval: @unchecked Sendable {
    private let lock = NSLock()
    private var fails = true
    func remove(_ url: URL) throws {
        if lock.withLock({
            let old = fails
            fails = false
            return old
        }) {
            throw StoreFailure.unavailable
        }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

@Suite struct AccountWiperTests {
    @Test(arguments: [false, true])
    func memberSignOutClearsGuestSecretsAndRecovery(unauthorized: Bool) async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = GuestRecoveryLocation.file(applicationSupport: root, namespace: .mock)
        try FileManager.default.createDirectory(
            at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("guest recovery".utf8).write(to: recovery)
        let preferences = root.appendingPathComponent("device-preferences.json")
        try Data("device preferences".utf8).write(to: preferences)
        let secrets = MemoryGuestSecretStore()
        await secrets.set("first-secret", for: "first")
        await secrets.set("second-secret", for: "second")
        let credentials = WipeCredentials()
        await credentials.write(try JSONEncoder().encode(StoredSession(token: "member-token", accountId: accountA)))
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let wiper = AccountWiper(
            applicationSupport: root, namespace: .mock, credentials: credentials, guestSecrets: secrets)
        var hooks = SessionTeardown()
        hooks.prepare = { try await wiper.recover() }
        hooks.beginWipe = { try await wiper.begin($0) }
        hooks.erase = { try await wiper.erase($0) }
        hooks.finishWipe = { try await wiper.finish() }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: hooks)
        #expect(try await controller.signOut(discardPending: false, unauthorized: unauthorized) == .signedOut)
        #expect(await secrets.get(for: "first") == nil)
        #expect(await secrets.get(for: "second") == nil)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(FileManager.default.fileExists(atPath: preferences.path))
        #expect(await credentials.data == nil)
    }

    @Test func pendingWipeRetriesGuestRecoveryDeletion() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recovery = GuestRecoveryLocation.file(applicationSupport: root, namespace: .mock)
        try FileManager.default.createDirectory(
            at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("guest recovery".utf8).write(to: recovery)
        let secrets = MemoryGuestSecretStore()
        await secrets.set("secret", for: "token")
        let credentials = WipeCredentials()
        let removal = FailingRemoval()
        let wiper = AccountWiper(
            applicationSupport: root, namespace: .mock, credentials: credentials, guestSecrets: secrets,
            remove: { url in
                if url == recovery { try removal.remove(url) }
            })
        let id = try AccountID(accountA)
        try await wiper.begin(id)
        await #expect(throws: StoreFailure.unavailable) { try await wiper.erase(id) }
        #expect(FileManager.default.fileExists(atPath: recovery.path))
        let restarted = AccountWiper(
            applicationSupport: root, namespace: .mock, credentials: credentials, guestSecrets: secrets)
        try await restarted.recover()
        #expect(await secrets.get(for: "token") == nil)
        #expect(!FileManager.default.fileExists(atPath: recovery.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("ChronoFlowMock/pending-wipe.json").path))
        #expect(await credentials.data == nil)
    }

    @Test func markerSurvivesPartialFailureAndRestartRemovesDirectoryAndCredentials() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try AccountID(accountA)
        let database = AccountDatabase(applicationSupport: root, namespace: .mock)
        try await database.open(accountID: id.rawValue)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: accountA, name: "Old", email: "old@example.test"))
        let directory = await database.directory(for: id)
        let sidecars = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(sidecars.contains(where: { $0.hasSuffix("-wal") }))
        #expect(sidecars.contains(where: { $0.hasSuffix("-shm") }))
        let credentials = WipeCredentials()
        let removal = FailingRemoval()
        let wiper = AccountWiper(
            applicationSupport: root, namespace: .mock, credentials: credentials, remove: { try removal.remove($0) })
        try await wiper.begin(id)
        let marker = root.appendingPathComponent("ChronoFlowMock/pending-wipe.json")
        #expect(try isBackupExcluded(marker))
        try await database.close()
        await #expect(throws: StoreFailure.unavailable) { try await wiper.erase(id) }
        #expect(FileManager.default.fileExists(atPath: marker.path))
        let restarted = AccountWiper(applicationSupport: root, namespace: .mock, credentials: credentials)
        try await restarted.recover()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(await credentials.data == nil)
        try await restarted.recover()
        let next = AccountDatabase(applicationSupport: root, namespace: .mock)
        try await next.open(accountID: accountB)
        #expect(try await AccountRepository(database: next).account() == nil)
        #expect(try await OutboxRepository(database: next).pending().isEmpty)
        try await next.close()
    }

    @Test func corruptMarkerBlocksRecoveryWithoutTouchingAnotherNamespace() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = WipeCredentials()
        let wiper = AccountWiper(applicationSupport: root, namespace: .api, credentials: credentials)
        try await wiper.begin(AccountID(accountA))
        let marker = root.appendingPathComponent("ChronoFlow/pending-wipe.json")
        try JSONEncoder().encode("../outside").write(to: marker)
        await #expect(throws: (any Error).self) { try await wiper.recover() }
        #expect(await credentials.data != nil)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        let mock = AccountWiper(applicationSupport: root, namespace: .mock, credentials: credentials)
        try await mock.recover()
        #expect(await credentials.data != nil)
    }
}

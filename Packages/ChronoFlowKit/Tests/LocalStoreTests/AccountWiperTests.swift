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

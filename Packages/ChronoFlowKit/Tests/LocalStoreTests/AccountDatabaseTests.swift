import AppCore
import Foundation
import GRDB
import Testing

@testable import LocalStore

struct AccountDatabaseTests {
    @Test(arguments: [
        "", "../account", "/tmp/escape", "account", accountA + "/x", " " + accountA, "{" + accountA + "}",
    ])
    func rejectsInvalidPaths(_ id: String) async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        await #expect(throws: StoreFailure.invalidAccountID) { try await store.open(accountID: id) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func walForeignKeysIsolationAndBackupExclusion() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for namespace in StorageNamespace.allCases {
            for id in [accountA, accountB] {
                let store = AccountDatabase(applicationSupport: root, namespace: namespace)
                try await store.open(accountID: id.uppercased())
                let directory = await store.directory(for: try AccountID(id))
                #expect(try isBackupExcluded(directory))
                #expect(try await store.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<6 {
                        group.addTask { () async throws -> Void in
                            #expect(try await store.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") } == 1)
                        }
                    }
                    try await group.waitForAll()
                }
                #expect(try await store.write { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") } == 1)
                #expect(try await store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM account") } == 0)
                try await store.write {
                    try $0.execute(
                        sql: "INSERT INTO account (id,name,email) VALUES (?,?,?)", arguments: [id, "Name", "email"])
                }
                await #expect(throws: StoreFailure.alreadyOpen) {
                    try await store.open(accountID: id == accountA ? accountB : accountA)
                }
                try await store.close()
                try await store.close()
                await #expect(throws: StoreFailure.closed) { try await store.read { _ in true } }
            }
        }
    }

    @Test func failedMigrationRollsBackWithoutDeletingExistingFile() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let existingDirectory = root.appendingPathComponent("ChronoFlow/Accounts/" + accountA)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        let existing = try DatabasePool(path: existingDirectory.appendingPathComponent("account-\(accountA).db").path)
        try await existing.write { db in
            try db.execute(sql: "CREATE TABLE sentinel (value TEXT); INSERT INTO sentinel VALUES ('preserved')")
        }
        try existing.close()
        let broken = AccountDatabase(applicationSupport: root) { db in
            try db.execute(sql: "CREATE TABLE partial (id TEXT)")
            throw StoreFailure.migration
        }
        await #expect(throws: StoreFailure.migration) { try await broken.open(accountID: accountA) }
        let directory = await broken.directory(for: try AccountID(accountA))
        let file = directory.appendingPathComponent("account-\(accountA).db")
        #expect(FileManager.default.fileExists(atPath: file.path))
        let pool = try DatabasePool(path: file.path)
        #expect(
            try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master WHERE name='partial'") }
                == 0)
        #expect(try await pool.read { try String.fetchOne($0, sql: "SELECT value FROM sentinel") } == "preserved")
        try pool.close()
        let recovered = AccountDatabase(applicationSupport: root)
        try await recovered.open(accountID: accountA)
        try await recovered.close()
        let corruptRoot = root.appendingPathComponent("corrupt")
        let corrupt = AccountDatabase(applicationSupport: corruptRoot)
        let corruptDirectory = await corrupt.directory(for: try AccountID(accountA))
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let corruptFile = corruptDirectory.appendingPathComponent("account-\(accountA).db")
        let bytes = Data("not a sqlite database".utf8)
        try bytes.write(to: corruptFile)
        await #expect(throws: StoreFailure.unavailable) { try await corrupt.open(accountID: accountA) }
        #expect(try Data(contentsOf: corruptFile) == bytes)
    }
}

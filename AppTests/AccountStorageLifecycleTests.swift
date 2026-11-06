import AppCore
import Foundation
import LocalStore
import XCTest

nonisolated final class AccountStorageLifecycleTests: XCTestCase {
    func testDirectoryDatabaseAndSidecarsRetainProtectionAndBackupExclusionAfterReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "store-protection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        let id = try AccountID("019a562b-8000-7000-8000-000000000001")
        let directory = await store.directory(for: id)
        for _ in 0..<2 {
            try await store.open(accountID: id.rawValue)
            try await store.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO account (id,name,email) VALUES (?,?,?)",
                    arguments: [id.rawValue, "Test", "test@example.test"])
            }
            XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            for name in [
                "", "account-\(id.rawValue).db", "account-\(id.rawValue).db-wal", "account-\(id.rawValue).db-shm",
            ] {
                let path = name.isEmpty ? directory : directory.appendingPathComponent(name)
                XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), path.lastPathComponent)
                #if targetEnvironment(simulator)
                    // The simulator accepts protection attributes but cannot read them back.
                    XCTAssertNoThrow(
                        try FileManager.default.setAttributes(
                            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                            ofItemAtPath: path.path))
                #else
                    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                    XCTAssertEqual(
                        attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
                #endif
            }
            try await store.close()
        }
    }
}

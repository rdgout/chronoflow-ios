import Foundation
import GRDB
import Testing

@testable import LocalStore

struct SchemaV1Tests {
    @Test func matchesFinalRNSchemaAndReopensIdempotently() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        let fixture = try JSONDecoder().decode(
            [String: SchemaTable].self,
            from:
                Data(
                    contentsOf: Bundle.module.url(
                        forResource: "rn-schema-v1", withExtension: "json", subdirectory: "Fixtures")!))
        for _ in 0..<2 {
            try await store.open(accountID: accountA)
            for (table, expected) in fixture {
                let columns = try await store.read { db in
                    try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map {
                        Column(
                            name: $0["name"], type: $0["type"], notnull: $0["notnull"], default: $0["dflt_value"],
                            pk: $0["pk"])
                    }
                }
                let actualColumns = columns.map(\.normalized).sorted { $0.name < $1.name }
                let expectedColumns = expected.columns.map(\.normalized).sorted { $0.name < $1.name }
                #expect(actualColumns == expectedColumns)
                let keys = try await store.read { db in
                    try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))").map {
                        ForeignKey(table: $0["table"], from: $0["from"], to: $0["to"], onDelete: $0["on_delete"])
                    }
                }
                #expect(keys == expected.foreignKeys)
            }
            #expect(
                try await store.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") } == [
                    "v1"
                ])
            let tables = try await store.read {
                try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            }
            #expect(Set(tables) == Set(fixture.keys).union(["grdb_migrations"]))
            try await store.close()
        }
    }

    @Test func foreignKeysCascadeAndRollbackRetainsUnrelatedCheckMarks() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        try await store.open(accountID: accountA)
        try await store.write { db in
            try db.execute(
                sql: "INSERT INTO trips (id,card,departure_utc) VALUES (?,?,?)", arguments: ["trip", "{}", "date"])
            try db.execute(
                sql: "INSERT INTO plan_versions (trip_id,input_hash,detail,received_at) VALUES (?,?,?,?)",
                arguments: ["trip", "hash", "{}", "date"])
            try db.execute(
                sql: "INSERT INTO check_marks VALUES (?,?,?,?,?,?,?)",
                arguments: ["trip", "hash", "sleep", "date", 0, "done", "date"])
        }
        await #expect(throws: (any Error).self) {
            try await store.write { db in
                try db.execute(sql: "DELETE FROM trips")
                throw StoreFailure.unavailable
            }
        }
        #expect(try await store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM plan_versions") } == 1)
        try await store.write { try $0.execute(sql: "DELETE FROM trips") }
        #expect(try await store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM plan_versions") } == 0)
        #expect(try await store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM check_marks") } == 1)
        try await store.close()
    }
}

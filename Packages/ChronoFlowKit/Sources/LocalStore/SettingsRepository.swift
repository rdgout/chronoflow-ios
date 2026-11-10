import AppCore
import GRDB

public struct SettingsRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func settings() async throws -> [SettingsRecord] {
        try await database.read { try SettingsRecord.fetchAll($0, sql: "SELECT * FROM settings ORDER BY section") }
    }

    public func values() async throws -> AsyncThrowingStream<[SettingsRecord], any Error> {
        try await database.observe { try SettingsRecord.fetchAll($0, sql: "SELECT * FROM settings ORDER BY section") }
    }

    public func upsert(_ record: SettingsRecord) async throws {
        try await database.write { db in
            var record = record
            if record.section == "bodyClock" {
                record.value = try .encoding(ProfilePreferences.bodyClock(record.value.decode(JSONObject.self)))
            } else if record.section == "readiness" {
                let body =
                    try SettingsRecord.fetchOne(db, key: "bodyClock")?.value.decode(JSONObject.self) ?? JSONObject()
                record.value = try .encoding(
                    ProfilePreferences.readiness(record.value.decode(JSONObject.self), bodyClock: body))
            }
            try record.save(db)
        }
    }

    public func upsertSecurity(_ value: JSONObject, permit: SessionMutationPermit) async throws {
        try await database.write(permit: permit) { db in
            try SettingsRecord(section: "security", value: .encoding(value)).save(db)
        }
    }

    public func remove(section: String) async throws {
        _ = try await database.write { try SettingsRecord.deleteOne($0, key: section) }
    }
}

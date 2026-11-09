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

    public func upsert(_ record: SettingsRecord) async throws { try await database.write { try record.save($0) } }

    public func remove(section: String) async throws {
        _ = try await database.write { try SettingsRecord.deleteOne($0, key: section) }
    }
}

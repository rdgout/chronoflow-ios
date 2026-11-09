import GRDB

public struct OutboxRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func pending() async throws -> [OutboxRecord] {
        try await database.read { try OutboxRecord.fetchAll($0, sql: "SELECT * FROM outbox ORDER BY created_at,id") }
    }

    public func values() async throws -> AsyncThrowingStream<[OutboxRecord], any Error> {
        try await database.observe { try OutboxRecord.fetchAll($0, sql: "SELECT * FROM outbox ORDER BY created_at,id") }
    }

    public func upsert(_ record: OutboxRecord) async throws { try await database.write { try record.save($0) } }

    public func remove(id: String) async throws {
        _ = try await database.write { try OutboxRecord.deleteOne($0, key: id) }
    }
}

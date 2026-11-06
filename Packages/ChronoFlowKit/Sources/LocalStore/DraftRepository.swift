import GRDB

public struct DraftRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func drafts() async throws -> [DraftRecord] {
        try await database.read { try DraftRecord.fetchAll($0, sql: "SELECT * FROM drafts ORDER BY updated_at,id") }
    }

    public func values() async throws -> AsyncThrowingStream<[DraftRecord], any Error> {
        try await database.observe { try DraftRecord.fetchAll($0, sql: "SELECT * FROM drafts ORDER BY updated_at,id") }
    }

    public func upsert(_ record: DraftRecord) async throws { try await database.write { try record.save($0) } }

    public func remove(id: String) async throws {
        _ = try await database.write { try DraftRecord.deleteOne($0, key: id) }
    }
}

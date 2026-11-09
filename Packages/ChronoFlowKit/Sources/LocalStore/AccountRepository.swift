import AppCore
import GRDB

public struct AccountRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func account() async throws -> AccountRecord? {
        let id = try await activeID()
        return try await database.read { try AccountRecord.fetchOne($0, key: id) }
    }

    public func upsert(_ record: AccountRecord) async throws {
        let id = try await activeID()
        guard record.id == id else { throw StoreFailure.invalidAccountID }
        try await database.write { try record.save($0) }
    }

    public func values() async throws -> AsyncThrowingStream<AccountRecord?, any Error> {
        let id = try await activeID()
        return try await database.observe { try AccountRecord.fetchOne($0, key: id) }
    }

    private func activeID() async throws -> String {
        guard let id = await database.accountID else { throw StoreFailure.closed }
        return id.rawValue
    }
}

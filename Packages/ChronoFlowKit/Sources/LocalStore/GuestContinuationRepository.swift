import AppCore
import GRDB

public struct GuestContinuationRepository: Sendable {
    private let database: AccountDatabase
    private let permit: SessionMutationPermit?
    private static let section = "guestContinuation"

    public init(database: AccountDatabase, permit: SessionMutationPermit? = nil) {
        self.database = database
        self.permit = permit
    }

    public func store(_ destination: GuestSessionContinuation) async throws {
        try await database.write(permit: permit) { db in
            try SettingsRecord(section: Self.section, value: .encoding(destination)).save(db)
        }
    }

    public func values() async throws -> AsyncThrowingStream<GuestSessionContinuation?, any Error> {
        try await database.observe { db in
            try SettingsRecord.fetchOne(db, key: Self.section)?.value.decode(GuestSessionContinuation.self)
        }
    }

    public func consume(gate: Gate) async throws -> GuestSessionContinuation? {
        guard gate == .app else { return nil }
        return try await database.write(permit: permit) { db in
            let destination = try SettingsRecord.fetchOne(db, key: Self.section)?.value.decode(
                GuestSessionContinuation.self)
            try SettingsRecord.deleteOne(db, key: Self.section)
            return destination
        }
    }
}

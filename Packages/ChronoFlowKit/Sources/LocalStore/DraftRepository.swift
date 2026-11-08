import AppCore
import Foundation
import GRDB

public struct DraftRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func drafts() async throws -> [DraftRecord] {
        try await database.read {
            try DraftRecord.fetchAll($0, sql: "SELECT * FROM drafts WHERE id != 'member-wizard' ORDER BY updated_at,id")
        }
    }

    public func values() async throws -> AsyncThrowingStream<[DraftRecord], any Error> {
        try await database.observe {
            try DraftRecord.fetchAll($0, sql: "SELECT * FROM drafts WHERE id != 'member-wizard' ORDER BY updated_at,id")
        }
    }

    public func upsert(_ record: DraftRecord) async throws { try await database.write { try record.save($0) } }

    public func remove(id: String, permit: SessionMutationPermit? = nil) async throws {
        _ = try await database.write(permit: permit) { try DraftRecord.deleteOne($0, key: id) }
    }
}

extension DraftRepository {
    public func recovery(now: Date, permit: SessionMutationPermit? = nil) async throws -> DraftRecord? {
        try await database.write(permit: permit) { db in
            guard let record = try DraftRecord.fetchOne(db, key: "member-wizard") else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions.insert(.withFractionalSeconds)
            guard
                let updated = formatter.date(from: record.updatedAt)
                    ?? ISO8601DateFormatter().date(from: record.updatedAt),
                now.timeIntervalSince(updated) < 30 * 60,
                record.wizardState != nil
            else {
                try DraftRecord.deleteOne(db, key: record.id)
                return nil
            }
            return record
        }
    }

    public func createRecovery(_ record: DraftRecord, permit: SessionMutationPermit? = nil) async throws {
        try await database.write(permit: permit) { db in
            guard record.id == "member-wizard", try DraftRecord.fetchOne(db, key: record.id) == nil else {
                throw CancellationError()
            }
            try record.insert(db)
        }
    }

    public func updateRecovery(
        _ record: DraftRecord, instance: String, revision: Int, permit: SessionMutationPermit? = nil
    ) async throws {
        try await database.write(permit: permit) { db in
            guard record.id == "member-wizard", let current = try DraftRecord.fetchOne(db, key: record.id),
                let state = try current.wizardState?.decode(JSONObject.self), state["instance"]?.string == instance
            else { throw CancellationError() }
            if case .number(let previous) = state["revision"], previous > Decimal(revision) { return }
            try record.save(db)
        }
    }

    public func deleteRecovery(instance: String, permit: SessionMutationPermit? = nil) async throws {
        try await database.write(permit: permit) { db in
            guard let record = try DraftRecord.fetchOne(db, key: "member-wizard"),
                try record.wizardState?.decode(JSONObject.self)["instance"]?.string == instance
            else { return }
            try DraftRecord.deleteOne(db, key: record.id)
        }
    }
}

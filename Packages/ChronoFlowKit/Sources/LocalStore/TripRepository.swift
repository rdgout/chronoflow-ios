import GRDB

public struct TripRepository: Sendable {
    public let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func trips() async throws -> [TripRecord] {
        try await database.read { try TripRecord.fetchAll($0, sql: "SELECT * FROM trips ORDER BY departure_utc,id") }
    }

    public func values() async throws -> AsyncThrowingStream<[TripRecord], any Error> {
        try await database.observe { try TripRecord.fetchAll($0, sql: "SELECT * FROM trips ORDER BY departure_utc,id") }
    }

    public func upsert(_ trip: TripRecord) async throws { try await database.write { try trip.save($0) } }

    public func remove(id: String) async throws {
        _ = try await database.write { try TripRecord.deleteOne($0, key: id) }
    }

    public func plan(tripID: String, inputHash: String) async throws -> PlanVersionRecord? {
        try await database.read {
            try PlanVersionRecord.fetchOne(
                $0, sql: "SELECT * FROM plan_versions WHERE trip_id=? AND input_hash=?",
                arguments: [tripID, inputHash])
        }
    }

    public func checks(tripID: String, inputHash: String) async throws -> [CheckMarkRecord] {
        try await database.read {
            try CheckMarkRecord.fetchAll(
                $0, sql: "SELECT * FROM check_marks WHERE trip_id=? AND input_hash=? ORDER BY type,local_date,ordinal",
                arguments: [tripID, inputHash])
        }
    }

    public func planValues(tripID: String, inputHash: String) async throws -> AsyncThrowingStream<
        PlanVersionRecord?, any Error
    > {
        try await database.observe {
            try PlanVersionRecord.fetchOne(
                $0, sql: "SELECT * FROM plan_versions WHERE trip_id=? AND input_hash=?",
                arguments: [tripID, inputHash])
        }
    }

    public func checkValues(tripID: String, inputHash: String) async throws -> AsyncThrowingStream<
        [CheckMarkRecord], any Error
    > {
        try await database.observe {
            try CheckMarkRecord.fetchAll(
                $0, sql: "SELECT * FROM check_marks WHERE trip_id=? AND input_hash=? ORDER BY type,local_date,ordinal",
                arguments: [tripID, inputHash])
        }
    }

    public func store(plan: PlanVersionRecord, checks: [CheckMarkRecord]) async throws {
        try await database.write { db in
            try plan.save(db)
            for check in checks { try check.save(db) }
        }
    }
}

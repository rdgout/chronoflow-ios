import AppCore
import GRDB

public struct TripPlanSnapshot: Sendable, Equatable {
    public var trip: TripRecord?
    public var plan: PlanVersionRecord?
    public var checks: [CheckMarkRecord]
    public var pendingChecks: [CheckOffChange]
}

extension TripRepository {
    public func detailValues(tripID: String) async throws -> AsyncThrowingStream<TripPlanSnapshot, any Error> {
        try await database.observe { db in
            let trip = try TripRecord.fetchOne(db, key: tripID)
            let plan = try trip?.currentInputHash.flatMap { hash in
                try PlanVersionRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM plan_versions WHERE trip_id=? AND input_hash=?",
                    arguments: [tripID, hash])
            }
            let checks = try CheckMarkRecord.fetchAll(
                db, sql: "SELECT * FROM check_marks WHERE trip_id=?", arguments: [tripID])
            let pending = try OutboxRecord.fetchAll(
                db, sql: "SELECT * FROM outbox WHERE kind='check-off' ORDER BY created_at,id"
            )
            .compactMap { row -> CheckOffChange? in
                guard case .checkOff(let change) = try row.change, change.tripID == tripID else { return nil }
                return change
            }
            return TripPlanSnapshot(trip: trip, plan: plan, checks: checks, pendingChecks: pending)
        }
    }
}

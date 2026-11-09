import AppCore
import GRDB

public struct TripPlanSnapshot: Sendable, Equatable {
    public var trip: TripRecord?
    public var plan: PlanVersionRecord?
    public var checks: [CheckMarkRecord] = []
    public var pendingChecks: [CheckOffChange] = []
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
                db, sql: "SELECT * FROM check_marks WHERE trip_id=? AND input_hash=? ORDER BY marked_at",
                arguments: [tripID, trip?.currentInputHash ?? ""])
            let pending = try StoreApplication.pending(db).compactMap { row -> CheckOffChange? in
                guard case .checkOff(let check) = try? row.change, check.tripID == tripID else { return nil }
                return check
            }
            return TripPlanSnapshot(trip: trip, plan: plan, checks: checks, pendingChecks: pending)
        }
    }
}

import GRDB

public struct TripPlanSnapshot: Sendable, Equatable {
    public var trip: TripRecord?
    public var plan: PlanVersionRecord?
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
            return TripPlanSnapshot(trip: trip, plan: plan)
        }
    }
}

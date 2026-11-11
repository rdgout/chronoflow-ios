import AppCore
import GRDB
import LocalStore

public struct SyncChanges: Sendable, Equatable {
    public var tripsAdded: Int
    public var tripsUpdated: Int
    public var tripsRemoved: Int
    public var planVersionsChanged: Int

    public init(tripsAdded: Int = 0, tripsUpdated: Int = 0, tripsRemoved: Int = 0, planVersionsChanged: Int = 0) {
        self.tripsAdded = tripsAdded
        self.tripsUpdated = tripsUpdated
        self.tripsRemoved = tripsRemoved
        self.planVersionsChanged = planVersionsChanged
    }
}

struct SyncSnapshot: Sendable {
    private struct Value: Sendable, Equatable {
        var trip: TripRecord
        var planVersion: String?
    }
    private var trips: [String: Value]

    static func read(_ database: AccountDatabase) async throws -> Self {
        try await database.read { db in
            var versions: [String: String] = [:]
            for row in try Row.fetchAll(
                db,
                sql: """
                    SELECT p.trip_id, p.detail_version FROM plan_versions p
                    JOIN trips t ON t.id=p.trip_id AND t.current_input_hash=p.input_hash
                    """)
            {
                let id: String = row["trip_id"]
                versions[id] = row["detail_version"] as String?
            }
            var trips: [String: Value] = [:]
            for var trip in try TripRecord.fetchAll(db) where !trip.deletedLocally && trip.deletedAt == nil {
                // Retention and receipt times describe this phone, not a server change.
                trip.keepOffline = false
                trip.card = try .encoding(trip.card.decode(JSONValue.self))
                trip.adaptation = try trip.adaptation.map { try .encoding($0.decode(JSONValue.self)) }
                trip.form = try trip.form.map { try .encoding($0.decode(JSONValue.self)) }
                trip.revision = try trip.revision.map { try .encoding($0.decode(JSONValue.self)) }
                trips[trip.id] = Value(trip: trip, planVersion: versions[trip.id])
            }
            return Self(trips: trips)
        }
    }

    func changes(to after: Self) -> SyncChanges {
        let beforeIDs = Set(trips.keys)
        let afterIDs = Set(after.trips.keys)
        let common = beforeIDs.intersection(afterIDs)
        let planChanges = Set(
            common.filter { id in
                guard let before = trips[id], let after = after.trips[id] else { return false }
                return before.trip.currentInputHash != after.trip.currentInputHash
                    || (before.planVersion != nil && after.planVersion != nil
                        && before.planVersion != after.planVersion)
            })
        return SyncChanges(
            tripsAdded: afterIDs.subtracting(beforeIDs).count,
            tripsUpdated: common.filter { trips[$0]?.trip != after.trips[$0]?.trip || planChanges.contains($0) }.count,
            tripsRemoved: beforeIDs.subtracting(afterIDs).count,
            planVersionsChanged: planChanges.count)
    }
}

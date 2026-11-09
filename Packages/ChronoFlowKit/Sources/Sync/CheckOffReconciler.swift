import AppCore
import Foundation
import LocalStore

public struct CheckOffReconciler: Sendable {
    public let pull: FullPull
    public init(pull: FullPull) { self.pull = pull }

    public func prepare(_ row: OutboxRecord, epoch: SyncEpoch, refresh: Bool = false) async throws -> OutboxRecord? {
        try epoch.check()
        guard case .checkOff(let change) = try row.change else { return row }
        let trip = try await pull.database.read { try TripRecord.fetchOne($0, key: change.tripID) }
        try epoch.check()
        guard let trip, trip.deletedAt == nil, !trip.deletedLocally else {
            try await pull.database.write(epoch: epoch) { db in
                try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [row.id])
            }
            return nil
        }
        if !refresh && trip.currentInputHash == change.planInputHash { return row }
        try await pull.fetchDetail(tripID: change.tripID, epoch: epoch)
        try epoch.check()
        return try await pull.database.write(epoch: epoch) { db in
            guard var storedRow = try OutboxRecord.fetchOne(db, key: row.id),
                let trip = try TripRecord.fetchOne(db, key: change.tripID), let hash = trip.currentInputHash,
                let plan = try PlanVersionRecord.fetchOne(
                    db, sql: "SELECT * FROM plan_versions WHERE trip_id=? AND input_hash=?", arguments: [trip.id, hash])
            else { throw DataFailure.server(status: nil) }
            let detail = try plan.decodedDetail()
            let key = CheckKeyView(type: change.type, localDate: change.localDate, ordinal: change.ordinal)
            let exists = detail.plan.blocks.contains { $0.actionable && $0.checkKey == key }
            guard exists else {
                try db.execute(sql: "DELETE FROM outbox WHERE id=?", arguments: [row.id])
                try db.execute(
                    sql:
                        "DELETE FROM check_marks WHERE trip_id=? AND input_hash=? AND type=? AND local_date=? AND ordinal=? AND marked_at<=?",
                    arguments: [
                        change.tripID, change.planInputHash, change.type.rawValue, change.localDate, change.ordinal,
                        row.createdAt,
                    ])
                return nil
            }
            var next = change
            next.planInputHash = hash
            storedRow.payload = try .encoding(next)
            if hash != change.planInputHash {
                storedRow.attempts = 0
                storedRow.lastError = nil
            }
            try storedRow.save(db)
            let newer = try StoreApplication.pending(db).contains { other in
                guard other.kind == "check-off", other.id != row.id,
                    other.createdAt > row.createdAt || (other.createdAt == row.createdAt && other.id > row.id),
                    case .checkOff(let check) = try? other.change
                else { return false }
                return check.tripID == change.tripID && check.type == change.type && check.localDate == change.localDate
                    && check.ordinal == change.ordinal
            }
            let mark = try CheckMarkRecord.fetchOne(
                db,
                sql:
                    "SELECT * FROM check_marks WHERE trip_id=? AND input_hash=? AND type=? AND local_date=? AND ordinal=?",
                arguments: [change.tripID, hash, change.type.rawValue, change.localDate, change.ordinal])
            if !newer && (mark == nil || mark!.markedAt <= row.createdAt) {
                try StoreApplication.setMark(next, at: row.createdAt, db: db)
            }
            return storedRow
        }
    }
}

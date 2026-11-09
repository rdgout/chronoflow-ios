import AppCore
import Foundation
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

extension TripRepository {
    public static func applyCards(_ items: [AppCore.TripListItem], at: String, db: Database) throws {
        let ids = Set(items.map { $0.card.id })
        guard ids.count == items.count, items.allSatisfy({ !$0.card.id.isEmpty && !$0.card.departureUtc.isEmpty })
        else { throw AppCore.DataFailure.server(status: nil) }
        for var trip in try TripRecord.fetchAll(db) where !ids.contains(trip.id) && trip.deletedAt == nil {
            trip.deletedAt = at
            try trip.save(db)
        }
        let pending = try StoreApplication.pending(db)
        for item in items {
            let id = item.card.id
            let departure = item.card.departureUtc
            var trip =
                try TripRecord.fetchOne(db, key: id)
                ?? TripRecord(id: id, card: .encoding(item.card), departureUtc: departure)
            guard !trip.deletedLocally else { continue }
            var card = item.card
            if pending.contains(where: { $0.kind == "complete-trip" && $0.referencedTripID == id }) {
                card.progress.status = .completed
                card.canComplete = false
            }
            trip.card = try .encoding(card)
            trip.adaptation = try item.adaptation.map { try .encoding($0) }
            trip.currentInputHash = item.planInputHash
            trip.keepOffline = item.keepOffline
            trip.departureUtc = departure
            trip.planStartUtc = item.planStartUtc
            trip.planStartZone = item.planStartZone
            trip.planEndUtc = item.planEndUtc
            trip.planEndDate = item.planEndDate
            trip.preparationDays = item.preparationDays
            trip.deletedAt = nil
            try trip.save(db)
            if let checks = item.checkState { try StoreApplication.checks(checks, tripID: id, db: db) }
        }
    }

    public static func applyDetail(_ response: AppCore.TripDetailResponse, tripID: String, at: String, db: Database)
        throws
    {
        let value = response.detail
        let hash = value.plan.meta.inputHash
        guard value.trip.id == tripID,
            !hash.isEmpty, hash == value.checkState.planInputHash
        else { throw AppCore.DataFailure.server(status: nil) }
        guard var trip = try TripRecord.fetchOne(db, key: tripID), !trip.deletedLocally, trip.deletedAt == nil else {
            return
        }
        try PlanVersionRecord(
            tripId: tripID, inputHash: hash, detail: JSONDocument(data: response.data), receivedAt: at,
            detailVersion: value.detailVersion
        ).save(db)
        trip.currentInputHash = hash
        try trip.save(db)
        try StoreApplication.checks(value.checkState, tripID: tripID, db: db)
    }

    public static func evictPlans(held: Set<String>, db: Database) throws {
        let pending = Set(try StoreApplication.pending(db).compactMap(\.referencedTripID))
        for var trip in try TripRecord.fetchAll(db) {
            guard !pending.contains(trip.id), !held.contains(trip.id),
                trip.deletedAt != nil || trip.deletedLocally || !trip.keepOffline
            else { continue }
            try db.execute(sql: "DELETE FROM plan_versions WHERE trip_id=?", arguments: [trip.id])
            try db.execute(sql: "DELETE FROM check_marks WHERE trip_id=?", arguments: [trip.id])
            if trip.deletedAt != nil || trip.deletedLocally {
                trip.currentInputHash = nil
                trip.keepOffline = false
                try trip.save(db)
            }
        }
    }
}

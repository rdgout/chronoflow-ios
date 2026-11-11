import AppCore
import Foundation
import LocalStore

public struct FullPullResult: Sendable, Equatable {
    public var changes = SyncChanges()
    public var verificationRequired = false
    public var retryAfter: TimeInterval?
    public init() {}
}

public struct FullPull: Sendable {
    public let database: AccountDatabase
    public let source: any DataSource
    public let retention: PlanRetention
    private let now: @Sendable () -> Date

    public init(
        database: AccountDatabase, source: any DataSource, retention: PlanRetention = PlanRetention(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.database = database
        self.source = source
        self.retention = retention
        self.now = now
    }

    public func run(epoch: SyncEpoch) async throws -> FullPullResult {
        try await database.validate(epoch: epoch)
        try epoch.check()
        let before = try await SyncSnapshot.read(database)
        let identity = try await source.fetchIdentity()
        try epoch.check()
        try await database.write(epoch: epoch) { db in
            try StoreApplication.identity(identity, accountID: epoch.accountID, db: db)
        }
        try epoch.check()
        var result = FullPullResult()
        if !identity.hasVerifiedEmail {
            result.verificationRequired = true
            return result
        }
        let account = try await source.fetchAccount()
        try epoch.check()
        guard account.id == epoch.accountID.rawValue else { throw StoreFailure.invalidAccountID }
        guard account.hasVerifiedEmail else { throw DataFailure.emailUnverified(status: 403) }
        let cards = try await source.fetchTrips()
        try epoch.check()
        let at = now().ISO8601Format()
        try await database.write(epoch: epoch) { db in
            try StoreApplication.snapshot(account, accountID: epoch.accountID, db: db)
            try TripRepository.applyCards(cards, at: at, db: db)
            try db.execute(sql: "UPDATE account SET synced_at=? WHERE id=?", arguments: [at, epoch.accountID.rawValue])
            try retention.withHeldPlans { try TripRepository.evictPlans(held: $0, db: db) }
        }
        try epoch.check()
        for item in cards {
            let id = item.card.id
            let needed = try await database.read { db in
                guard let trip = try TripRecord.fetchOne(db, key: id), !trip.deletedLocally, trip.deletedAt == nil
                else { return false }
                return try retention.withHeldPlans { held in
                    guard trip.keepOffline || held.contains(id) else { return false }
                    let stored = try PlanVersionRecord.fetchOne(
                        db, sql: "SELECT * FROM plan_versions WHERE trip_id=? AND input_hash=?",
                        arguments: [id, item.planInputHash])
                    return stored == nil || stored?.detailVersion != item.detailVersion
                }
            }
            try epoch.check()
            guard needed else { continue }
            do { try await fetchDetail(tripID: id, epoch: epoch) } catch is CancellationError {
                throw CancellationError()
            } catch let error as DataFailure {
                try epoch.check()
                switch error {
                case .unauthorized, .emailUnverified, .offline, .throttled: throw error
                case .server(status: 404): break
                default: result.retryAfter = 1
                }
            } catch {
                try epoch.check()
                result.retryAfter = 1
            }
        }
        try epoch.check()
        let after = try await SyncSnapshot.read(database)
        result.changes = before.changes(to: after)
        try epoch.check()
        return result
    }

    public func fetchDetail(tripID: String, epoch: SyncEpoch) async throws {
        try await database.validate(epoch: epoch)
        try epoch.check()
        let value = try await source.fetchTripDetail(id: tripID)
        try epoch.check()
        let at = now().ISO8601Format()
        try await database.write(epoch: epoch) { db in
            try TripRepository.applyDetail(value, tripID: tripID, at: at, db: db)
        }
        try epoch.check()
    }
}

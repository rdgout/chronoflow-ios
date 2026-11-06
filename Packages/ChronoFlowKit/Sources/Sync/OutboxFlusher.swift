import AppCore
import Foundation
import LocalStore

public struct OutboxFlushResult: Sendable, Equatable {
    public var refusals: [SyncRefusal] = []
    public var retryAfter: TimeInterval?
    public var parked: Int = 0
    public var offline = false
    public init() {}
}

public struct OutboxFlusher: Sendable {
    public let database: AccountDatabase
    public let source: any DataSource
    private let now: @Sendable () -> Date
    public typealias PrepareCheck = @Sendable (OutboxRecord, SyncEpoch) async throws -> OutboxRecord?
    private let prepareCheck: PrepareCheck
    private let refreshCheck: PrepareCheck

    public init(
        database: AccountDatabase, source: any DataSource,
        now: @escaping @Sendable () -> Date = { Date() },
        prepareCheck: @escaping PrepareCheck = { row, _ in row },
        refreshCheck: @escaping PrepareCheck = { row, _ in row }
    ) {
        self.database = database
        self.source = source
        self.now = now
        self.prepareCheck = prepareCheck
        self.refreshCheck = refreshCheck
    }

    public func run(epoch: SyncEpoch) async throws -> OutboxFlushResult {
        try await database.validate(epoch: epoch)
        try await database.validate(epoch: epoch)
        try epoch.check()
        let rows = try await OutboxRepository(database: database).pending()
        try epoch.check()
        var blocked = Set<String>()
        var result = OutboxFlushResult()
        for initial in rows {
            try epoch.check()
            guard !blocked.contains(initial.dependency) else { continue }
            guard let current = try await database.read({ db in try OutboxRecord.fetchOne(db, key: initial.id) }) else {
                continue
            }
            try epoch.check()
            var row = current
            do {
                if case .unsupported = try row.change {
                    blocked.insert(row.dependency)
                    result.parked += 1
                    continue
                }
                if row.kind == "check-off" {
                    guard let prepared = try await prepareCheck(row, epoch) else { continue }
                    try epoch.check()
                    row = prepared
                }
                for attempt in 0..<2 {
                    do {
                        try epoch.check()
                        let receipt = try await source.send(row.change)
                        try epoch.check()
                        let sent = row
                        try await database.write(epoch: epoch) { db in
                            try StoreApplication.receipt(receipt, for: sent, accountID: epoch.accountID, db: db)
                        }
                        try epoch.check()
                        break
                    } catch let error as DataFailure where row.kind == "check-off" && Self.isStale(error) {
                        if attempt == 1 { throw error }
                        guard let refreshed = try await refreshCheck(row, epoch) else { break }
                        try epoch.check()
                        row = refreshed
                    }
                }
            } catch is CancellationError { throw CancellationError() } catch {
                try epoch.check()
                let failure = error as? DataFailure ?? .server(status: nil)
                if case .unauthorized = failure { throw failure }
                if case .emailUnverified = failure { throw failure }
                if case .unsupported = failure {
                    result.parked += 1
                    blocked.insert(row.dependency)
                    continue
                }
                let sent = row
                if OutboxFailurePolicy.isFinal(failure) && !(row.kind == "check-off" && Self.isStale(failure)) {
                    let refusal = SyncRefusal(
                        id: row.id, kind: row.kind, status: failure.status,
                        failedAt: now().ISO8601Format(), lastError: OutboxFailurePolicy.sanitized(failure))
                    try await database.write(epoch: epoch) { db in
                        try StoreApplication.setting("syncFailure", value: .encoding(refusal), db: db)
                        try StoreApplication.refuse(sent, accountID: epoch.accountID, db: db)
                    }
                    result.refusals.append(refusal)
                } else {
                    let attempts = try await database.write(epoch: epoch) { db in
                        try db.execute(
                            sql: "UPDATE outbox SET attempts=attempts+1,last_error=? WHERE id=?",
                            arguments: [OutboxFailurePolicy.sanitized(failure), sent.id])
                        return try StoreApplication.pending(db).first(where: { $0.id == sent.id })?.attempts ?? 0
                    }
                    let retryAfter: TimeInterval
                    if case .throttled(let seconds, _) = failure { retryAfter = seconds } else { retryAfter = 0 }
                    result.retryAfter = max(
                        result.retryAfter ?? 0,
                        OutboxFailurePolicy.retryDelay(attempts: max(0, attempts - 1), retryAfter: retryAfter))
                    blocked.insert(row.dependency)
                    if case .offline = failure {
                        result.offline = true
                        return result
                    }
                }
            }
        }
        return result
    }

    public static func isStale(_ failure: DataFailure) -> Bool {
        if case .conflict = failure { return true }
        if case .validation(let fields, _) = failure {
            return fields["plan_input_hash"] != nil
                || fields["form"]?.key == "This plan has changed. Refresh it before marking this step."
        }
        return false
    }
}

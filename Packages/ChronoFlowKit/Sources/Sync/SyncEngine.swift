import AppCore
import Foundation
import LocalStore

public actor SyncEngine {
    private let database: AccountDatabase
    private let source: any DataSource
    private let epoch: SyncEpoch
    public let retention: PlanRetention
    private let scheduler: SyncScheduler
    private let isOnline: @Sendable () async -> Bool
    private var flight: Task<SyncResult, any Error>?
    private var flightEpoch: SyncEpoch?
    private var timer: Task<Void, Never>?
    private var timerID: UInt64 = 0
    private var rerun = false
    private var stopped = false
    private var observers: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]

    public init(
        database: AccountDatabase, source: any DataSource, epoch: SyncEpoch,
        retention: PlanRetention = PlanRetention(), scheduler: SyncScheduler = SyncScheduler(),
        isOnline: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.database = database
        self.source = source
        self.epoch = epoch
        self.retention = retention
        self.scheduler = scheduler
        self.isOnline = isOnline
    }

    public func events() -> AsyncStream<SyncEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(bufferingPolicy: .bufferingNewest(32))
        guard !stopped else {
            continuation.finish()
            return stream
        }
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    public func requestSync() {
        guard !stopped else { return }
        if flight != nil {
            rerun = true
            return
        }
        cancelTimer()
        let id = timerID
        timer = Task { [weak self, scheduler] in
            do {
                try await scheduler.sleep(1)
                try Task.checkCancellation()
                await self?.timerFired(id)
            } catch {}
        }
    }

    private func timerFired(_ id: UInt64) async {
        guard timerID == id, !stopped else { return }
        timer = nil
        _ = try? await refreshNow()
    }
    @discardableResult
    private func cancelTimer() -> Task<Void, Never>? {
        let pending = timer
        timerID &+= 1
        timer?.cancel()
        timer = nil
        return pending
    }

    public func refreshNow() async throws -> SyncResult {
        try Task.checkCancellation()
        try epoch.check()
        guard !stopped else { throw CancellationError() }
        try await database.validate(epoch: epoch)
        try epoch.check()
        guard !stopped else { throw CancellationError() }
        cancelTimer()
        let task: Task<SyncResult, any Error>
        if let flight {
            rerun = true
            task = flight
        } else {
            rerun = false
            let runEpoch = epoch.child()
            flightEpoch = runEpoch
            let candidate = Task { try await self.runFlights(epoch: runEpoch) }
            flight = candidate
            task = candidate
        }
        let cancellationEpoch = flightEpoch
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            cancellationEpoch?.invalidate()
            task.cancel()
        }
        try Task.checkCancellation()
        try epoch.check()
        return result
    }

    private func runFlights(epoch runEpoch: SyncEpoch) async throws -> SyncResult {
        defer {
            flight = nil
            flightEpoch = nil
            rerun = false
        }
        var result: SyncResult
        repeat {
            try runEpoch.check()
            emit(.started(accountID: epoch.accountID, epoch: epoch.generation))
            result = try await runOnce(epoch: runEpoch)
            try runEpoch.check()
            emit(.finished(accountID: epoch.accountID, epoch: epoch.generation, result: result))
            guard result.state == .idle, result.retryAfter == nil else { return result }
            if rerun { rerun = false } else { return result }
        } while true
    }

    private func runOnce(epoch: SyncEpoch) async throws -> SyncResult {
        var state: SyncState = .idle
        var retryAfter: TimeInterval?
        var refusals: [SyncRefusal] = []
        do {
            let online = await isOnline()
            try epoch.check()
            if online {
                let flush = try await OutboxFlusher(database: database, source: source, now: scheduler.now).run(
                    epoch: epoch)
                try epoch.check()
                refusals = flush.refusals
                retryAfter = flush.retryAfter
                if flush.offline {
                    state = .offline
                } else {
                    let pull = try await FullPull(
                        database: database, source: source, retention: retention, now: scheduler.now
                    ).run(epoch: epoch)
                    try epoch.check()
                    if pull.verificationRequired { state = .verificationRequired }
                    if let delay = pull.retryAfter { retryAfter = max(retryAfter ?? 0, delay) }
                }
            } else {
                state = .offline
            }
        } catch is CancellationError { throw CancellationError() } catch {
            try epoch.check()
            switch error as? DataFailure {
            case .offline: state = .offline
            case .unauthorized: state = .unauthorized
            case .emailUnverified:
                state = .verificationRequired
                try await database.write(epoch: epoch) { db in
                    try db.execute(
                        sql: "UPDATE account SET has_verified_email=0 WHERE id=?", arguments: [epoch.accountID.rawValue]
                    )
                }
                try epoch.check()
            case .throttled(let seconds, _):
                state = .failed
                retryAfter = seconds
            default:
                state = .failed
                retryAfter = max(retryAfter ?? 0, 1)
            }
        }
        let pending = try await OutboxRepository(database: database).pending().count
        try epoch.check()
        return SyncResult(state: state, pendingCount: pending, retryAfter: retryAfter, refusals: refusals)
    }

    private func emit(_ event: SyncEvent) {
        guard !stopped, (try? epoch.check()) != nil else { return }
        for observer in observers.values { observer.yield(event) }
    }

    public func cancelAndWait() async {
        stopped = true
        let pendingTimer = cancelTimer()
        flightEpoch?.invalidate()
        flight?.cancel()
        let pending = flight
        _ = await pending?.result
        await pendingTimer?.value
        for observer in observers.values { observer.finish() }
        observers.removeAll()
    }
}

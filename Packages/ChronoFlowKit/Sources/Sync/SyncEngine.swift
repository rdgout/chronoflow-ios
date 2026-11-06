import AppCore
import Foundation
import LocalStore

public actor SyncEngine {
    private let database: AccountDatabase
    private var source: (any DataSource)?
    private let epoch: SyncEpoch
    public let retention: PlanRetention
    private let scheduler: SyncScheduler
    private let isOnline: @Sendable () async -> Bool
    private var flight: Task<SyncResult, any Error>?
    private var flightEpoch: SyncEpoch?
    private var flightWaiters: RefreshWaiters?
    var waitingRefreshCount: Int { flightWaiters?.count ?? 0 }
    private var timer: Task<Void, Never>?
    private var canceledTimers: [UInt64: Task<Void, Never>] = [:]
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
        let canceledID = timerID
        timerID &+= 1
        timer?.cancel()
        if let pending {
            canceledTimers[canceledID] = pending
            Task { [weak self] in
                await pending.value
                await self?.timerDrained(canceledID)
            }
        }
        timer = nil
        return pending
    }

    private func timerDrained(_ id: UInt64) { canceledTimers.removeValue(forKey: id) }

    public func refreshNow() async throws -> SyncResult {
        try Task.checkCancellation()
        try epoch.check()
        guard !stopped else { throw CancellationError() }
        try await database.validate(epoch: epoch)
        try Task.checkCancellation()
        try epoch.check()
        guard !stopped else { throw CancellationError() }
        cancelTimer()
        let task: Task<SyncResult, any Error>
        let waiters: RefreshWaiters
        if let flight, let flightWaiters {
            rerun = true
            task = flight
            waiters = flightWaiters
        } else {
            rerun = false
            let runEpoch = epoch.child()
            flightEpoch = runEpoch
            let candidate = Task { try await self.runFlights(epoch: runEpoch) }
            flight = candidate
            task = candidate
            waiters = RefreshWaiters(task: candidate, epoch: runEpoch)
            flightWaiters = waiters
        }
        let id = UUID()
        waiters.add(id)
        defer { waiters.remove(id) }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            waiters.cancel(id)
        }
        try Task.checkCancellation()
        try epoch.check()
        return result
    }

    private func runFlights(epoch runEpoch: SyncEpoch) async throws -> SyncResult {
        defer {
            flight = nil
            flightEpoch = nil
            flightWaiters = nil
            rerun = false
        }
        var result: SyncResult
        var retryAfter: TimeInterval?
        var refusals: [SyncRefusal] = []
        try runEpoch.check()
        emit(.started(accountID: epoch.accountID, epoch: epoch.generation))
        repeat {
            rerun = false
            try runEpoch.check()
            result = try await runOnce(epoch: runEpoch)
            try runEpoch.check()
            if let delay = result.retryAfter { retryAfter = max(retryAfter ?? 0, delay) }
            refusals.append(contentsOf: result.refusals)
            if result.state == .unauthorized || result.state == .verificationRequired { break }
        } while rerun
        let merged = SyncResult(
            state: result.state, pendingCount: result.pendingCount, retryAfter: retryAfter, refusals: refusals)
        emit(.finished(accountID: epoch.accountID, epoch: epoch.generation, result: merged))
        return merged
    }

    private func runOnce(epoch: SyncEpoch) async throws -> SyncResult {
        guard let source else { throw CancellationError() }
        var state: SyncState = .idle
        var retryAfter: TimeInterval?
        var refusals: [SyncRefusal] = []
        do {
            let online = await isOnline()
            try epoch.check()
            if online {
                if try await AccountRepository(database: database).account()?.hasVerifiedEmail == false {
                    let identity = try await source.fetchIdentity()
                    try epoch.check()
                    try await database.write(epoch: epoch) { db in
                        try StoreApplication.identity(identity, accountID: epoch.accountID, db: db)
                    }
                    if !identity.hasVerifiedEmail {
                        return SyncResult(
                            state: .verificationRequired,
                            pendingCount: try await OutboxRepository(database: database).pending().count)
                    }
                }
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
        let timers = canceledTimers
        canceledTimers.removeAll()
        for timer in timers.values { await timer.value }
        source = nil
        retention.clear()
        for observer in observers.values { observer.finish() }
        observers.removeAll()
    }
}

private final class RefreshWaiters: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var ids: Set<UUID> = []
    private let task: Task<SyncResult, any Error>
    private let epoch: SyncEpoch

    init(task: Task<SyncResult, any Error>, epoch: SyncEpoch) {
        self.task = task
        self.epoch = epoch
    }

    var count: Int { lock.withLock { ids.count } }
    func add(_ id: UUID) { lock.withLock { _ = ids.insert(id) } }
    func remove(_ id: UUID) { lock.withLock { _ = ids.remove(id) } }
    func cancel(_ id: UUID) {
        lock.withLock {
            guard ids.remove(id) != nil, ids.isEmpty else { return }
            epoch.invalidate()
            task.cancel()
        }
    }
}

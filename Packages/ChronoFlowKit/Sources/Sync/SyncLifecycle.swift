import AppCore
import Foundation
import LocalStore

public protocol SyncPathMonitoring: Sendable {
    func updates() async -> AsyncStream<Bool>
    func stop() async
}

public actor SyncLifecycle {
    public let engine: SyncEngine
    private let database: AccountDatabase
    private let epoch: SyncEpoch
    private let scheduler: SyncScheduler
    private let path: (any SyncPathMonitoring)?
    private let unauthorized: @Sendable (UInt64) async -> Void
    private let verification: @Sendable (UInt64) async -> Void
    private var listeners: [Task<Void, Never>] = []
    private var retry: Task<Void, Never>?
    private var canceledTimers: [UInt64: Task<Void, Never>] = [:]
    private var retryID: UInt64 = 0
    private var failures = 0
    private var serverDeadline: Date?
    private var lastResult: SyncResult?
    private var started = false
    private var stopped = false
    private var unauthorizedSent = false

    public init(
        database: AccountDatabase, source: any DataSource, epoch: SyncEpoch,
        scheduler: SyncScheduler = SyncScheduler(), path: (any SyncPathMonitoring)? = nil,
        unauthorized: @escaping @Sendable (UInt64) async -> Void = { _ in },
        verification: @escaping @Sendable (UInt64) async -> Void = { _ in }
    ) {
        self.database = database
        self.epoch = epoch
        self.scheduler = scheduler
        self.path = path
        self.unauthorized = unauthorized
        self.verification = verification
        engine = SyncEngine(database: database, source: source, epoch: epoch, scheduler: scheduler)
    }

    public func start() async throws {
        guard !started, !stopped else { return }
        started = true
        let events = await engine.events()
        let rows = try await OutboxRepository(database: database).values()
        listeners.append(
            Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { return }
                    if case .finished(_, _, let result) = event { await self?.finished(result) }
                }
            })
        listeners.append(
            Task { [weak self] in
                var previous: Set<String> = []
                do {
                    for try await value in rows {
                        guard !Task.isCancelled else { return }
                        let ids = Set(value.map(\.id))
                        if !ids.subtracting(previous).isEmpty { await self?.requestSync() }
                        previous = ids
                    }
                } catch {}
            })
        if let path {
            let updates = await path.updates()
            listeners.append(
                Task { [weak self] in
                    var wasOffline = false
                    for await online in updates {
                        guard !Task.isCancelled else { return }
                        if !online {
                            wasOffline = true
                        } else if wasOffline {
                            wasOffline = false
                            await self?.requestSync()
                        }
                    }
                })
        }
        await requestSync()
    }

    public func requestSync() async {
        guard !stopped, !unauthorizedSent, retry == nil else { return }
        await engine.requestSync()
    }

    public func refreshNow() async throws -> SyncResult {
        try epoch.check()
        guard !stopped, !unauthorizedSent else { throw CancellationError() }
        if let serverDeadline, serverDeadline > scheduler.now(), let lastResult { return lastResult }
        cancelRetry()
        return try await engine.refreshNow()
    }

    private func finished(_ result: SyncResult) async {
        guard !stopped, (try? epoch.check()) != nil else { return }
        lastResult = result
        switch result.state {
        case .unauthorized:
            guard !unauthorizedSent else { return }
            unauthorizedSent = true
            cancelRetry()
            // Run outside the event listener: wipe drains that listener and the engine flight.
            Task { [unauthorized, epoch] in await unauthorized(epoch.generation) }
        case .verificationRequired:
            failures = 0
            cancelRetry()
            Task { [verification, epoch] in await verification(epoch.generation) }
        case .offline:
            cancelRetry()
        case .idle, .failed:
            guard result.state == .failed || result.retryAfter != nil else {
                failures = 0
                serverDeadline = nil
                cancelRetry()
                return
            }
            let exponential = min(pow(2, Double(min(failures, 9))), 300)
            failures += 1
            let delay = max(exponential, result.retryAfter ?? 0)
            serverDeadline = result.retryAfter.map { scheduler.now().addingTimeInterval($0) }
            cancelRetry()
            let id = retryID
            retry = Task { [weak self, scheduler] in
                do {
                    try await scheduler.sleep(delay)
                    try Task.checkCancellation()
                    await self?.retryFired(id)
                } catch {}
            }
        }
    }

    private func retryFired(_ id: UInt64) async {
        guard !stopped, id == retryID else { return }
        retry = nil
        serverDeadline = nil
        _ = try? await engine.refreshNow()
    }

    @discardableResult private func cancelRetry() -> Task<Void, Never>? {
        let old = retry
        let canceledID = retryID
        retryID &+= 1
        retry?.cancel()
        if let old {
            canceledTimers[canceledID] = old
            Task { [weak self] in
                await old.value
                await self?.timerDrained(canceledID)
            }
        }
        retry = nil
        return old
    }

    private func timerDrained(_ id: UInt64) { canceledTimers.removeValue(forKey: id) }

    public func stop() async {
        stopped = true
        epoch.invalidate()
        let timer = cancelRetry()
        let old = listeners
        listeners.removeAll()
        for task in old { task.cancel() }
        await path?.stop()
        await engine.cancelAndWait()
        for task in old { await task.value }
        await timer?.value
        let timers = canceledTimers
        canceledTimers.removeAll()
        for timer in timers.values { await timer.value }
        lastResult = nil
    }
}

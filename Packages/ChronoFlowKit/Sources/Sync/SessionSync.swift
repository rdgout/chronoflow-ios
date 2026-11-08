import AppCore
import Foundation
import LocalStore

public actor SessionSync {
    public nonisolated let retention = PlanRetention()
    private let accounts: SessionAccountDatabase
    private let source: @Sendable (StoredSession) async -> any DataSource
    private let isCurrent: @Sendable (StoredSession, UInt64) async -> Bool
    private let unauthorized: @Sendable (UInt64) async -> Void
    private let verification: @Sendable (UInt64) async -> Void
    private var lifecycle: SyncLifecycle?
    private var eventTask: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]
    private var latestEvent: SyncEvent?
    private var enabled = true
    private var generation: UInt64 = 0
    private let scheduler: SyncScheduler
    private let makePath: @Sendable () -> (any SyncPathMonitoring)?
    private var retryContext: (epoch: UInt64, state: SyncRetryState)?
    private var attachedEpoch: UInt64?

    public init(
        accounts: SessionAccountDatabase,
        scheduler: SyncScheduler = SyncScheduler(),
        makePath: @escaping @Sendable () -> (any SyncPathMonitoring)? = { nil },
        source: @escaping @Sendable (StoredSession) async -> any DataSource,
        isCurrent: @escaping @Sendable (StoredSession, UInt64) async -> Bool = { _, _ in true },
        unauthorized: @escaping @Sendable (UInt64) async -> Void,
        verification: @escaping @Sendable (UInt64) async -> Void
    ) {
        self.accounts = accounts
        self.scheduler = scheduler
        self.makePath = makePath
        self.source = source
        self.isCurrent = isCurrent
        self.unauthorized = unauthorized
        self.verification = verification
    }

    public nonisolated func requestStart(controller: SessionController, epoch: UInt64) async {
        guard let current = await controller.activeSession(), current.epoch == epoch else { return }
        Task { await self.start(session: current.session, epoch: epoch) }
    }

    public func start(session: StoredSession, epoch: UInt64) async {
        let current = await isCurrent(session, epoch)
        guard enabled, current else { return }
        if attachedEpoch == epoch, let lifecycle {
            await lifecycle.requestSync()
            return
        }
        generation &+= 1
        let generation = generation
        latestEvent = nil
        let old = lifecycle
        lifecycle = nil
        let oldEvents = eventTask
        eventTask = nil
        oldEvents?.cancel()
        await oldEvents?.value
        await old?.stop()
        guard self.generation == generation else { return }
        guard let database = await accounts.activeDatabase(), let id = try? AccountID(session.accountId) else { return }
        let source = await source(session)
        let stillCurrent = await isCurrent(session, epoch)
        guard enabled, self.generation == generation, stillCurrent else { return }
        let lifecycle = SyncLifecycle(
            database: database, source: source, epoch: SyncEpoch(accountID: id, generation: epoch),
            scheduler: scheduler, retryState: retryContext?.epoch == epoch ? retryContext!.state : SyncRetryState(),
            path: makePath(), retention: retention, unauthorized: unauthorized, verification: verification)
        self.lifecycle = lifecycle
        attachedEpoch = epoch
        retryContext = nil
        let events = await lifecycle.engine.events()
        guard self.generation == generation else { return }
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                await self?.publish(event, generation: generation)
            }
        }
        do { try await lifecycle.start() } catch {
            await lifecycle.stop()
            if self.generation == generation { self.lifecycle = nil }
        }
        if self.generation != generation { await lifecycle.stop() }
    }

    public func resume(session: StoredSession, epoch: UInt64) async {
        guard enabled, await isCurrent(session, epoch) else { return }
        if attachedEpoch == epoch, let lifecycle {
            await lifecycle.requestSync()
        } else {
            await start(session: session, epoch: epoch)
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        if !enabled { await detach(preservingRetry: true) }
    }

    public func requestSync() async { await lifecycle?.requestSync() }
    public func refreshNow() async throws -> SyncResult? { try await lifecycle?.refreshNow() }
    public func stop() async { await detach(preservingRetry: false) }

    public func fetchDetail(tripID: String, session: StoredSession, epoch: UInt64) async throws {
        guard enabled, await isCurrent(session, epoch) else { throw CancellationError() }
        if attachedEpoch != epoch || lifecycle == nil { await start(session: session, epoch: epoch) }
        guard enabled, attachedEpoch == epoch, let lifecycle, await isCurrent(session, epoch) else {
            throw CancellationError()
        }
        do {
            try await lifecycle.engine.fetchDetail(tripID: tripID)
        } catch let failure as DataFailure {
            guard await isCurrent(session, epoch) else { throw CancellationError() }
            switch failure {
            case .unauthorized: await unauthorized(epoch)
            case .emailUnverified: await verification(epoch)
            default: break
            }
            throw failure
        }
    }

    public func events() -> AsyncStream<SyncEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        if let latestEvent { continuation.yield(latestEvent) }
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish(_ event: SyncEvent, generation: UInt64) {
        guard self.generation == generation else { return }
        latestEvent = event
        for observer in observers.values { observer.yield(event) }
    }

    private func detach(preservingRetry: Bool) async {
        generation &+= 1
        let generation = generation
        let epoch = attachedEpoch
        attachedEpoch = nil
        let previous = lifecycle
        lifecycle = nil
        latestEvent = nil
        let previousEvents = eventTask
        eventTask = nil
        previousEvents?.cancel()
        await previousEvents?.value
        if !preservingRetry {
            retryContext = nil
            retention.clear()
        }
        await previous?.stop()
        if preservingRetry, self.generation == generation, let epoch, let previous {
            retryContext = (epoch, await previous.retryState)
        }
    }
    deinit {
        eventTask?.cancel()
        for observer in observers.values { observer.finish() }
    }
}

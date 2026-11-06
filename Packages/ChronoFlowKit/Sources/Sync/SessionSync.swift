import AppCore
import Foundation
import LocalStore

public actor SessionSync {
    private let accounts: SessionAccountDatabase
    private let source: @Sendable (StoredSession) async -> any DataSource
    private let isCurrent: @Sendable (StoredSession, UInt64) async -> Bool
    private let unauthorized: @Sendable (UInt64) async -> Void
    private let verification: @Sendable (UInt64) async -> Void
    private var lifecycle: SyncLifecycle?
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

    public func start(session: StoredSession, epoch: UInt64) async {
        let current = await isCurrent(session, epoch)
        guard enabled, current else { return }
        if attachedEpoch == epoch, let lifecycle {
            await lifecycle.requestSync()
            return
        }
        generation &+= 1
        let generation = generation
        let old = lifecycle
        lifecycle = nil
        await old?.stop()
        guard self.generation == generation else { return }
        guard let database = await accounts.activeDatabase(), let id = try? AccountID(session.accountId) else { return }
        let source = await source(session)
        let stillCurrent = await isCurrent(session, epoch)
        guard enabled, self.generation == generation, stillCurrent else { return }
        let lifecycle = SyncLifecycle(
            database: database, source: source, epoch: SyncEpoch(accountID: id, generation: epoch),
            scheduler: scheduler, retryState: retryContext?.epoch == epoch ? retryContext!.state : SyncRetryState(),
            path: makePath(), unauthorized: unauthorized, verification: verification)
        self.lifecycle = lifecycle
        attachedEpoch = epoch
        retryContext = nil
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

    private func detach(preservingRetry: Bool) async {
        generation &+= 1
        let generation = generation
        let epoch = attachedEpoch
        attachedEpoch = nil
        let previous = lifecycle
        lifecycle = nil
        if !preservingRetry { retryContext = nil }
        await previous?.stop()
        if preservingRetry, self.generation == generation, let epoch, let previous {
            retryContext = (epoch, await previous.retryState)
        }
    }
}

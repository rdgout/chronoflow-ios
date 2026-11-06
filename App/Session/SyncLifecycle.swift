import AppCore
import Foundation
import LocalStore
import Sync

actor SessionSync {
    private let accounts: SessionAccountDatabase
    private let source: @Sendable (StoredSession) async -> any DataSource
    private let isCurrent: @Sendable (StoredSession, UInt64) async -> Bool
    private let unauthorized: @Sendable (UInt64) async -> Void
    private let verification: @Sendable (UInt64) async -> Void
    private var lifecycle: SyncLifecycle?
    private var enabled = true
    private var generation: UInt64 = 0
    private var attachedEpoch: UInt64?

    init(
        accounts: SessionAccountDatabase,
        source: @escaping @Sendable (StoredSession) async -> any DataSource,
        isCurrent: @escaping @Sendable (StoredSession, UInt64) async -> Bool = { _, _ in true },
        unauthorized: @escaping @Sendable (UInt64) async -> Void,
        verification: @escaping @Sendable (UInt64) async -> Void
    ) {
        self.accounts = accounts
        self.source = source
        self.isCurrent = isCurrent
        self.unauthorized = unauthorized
        self.verification = verification
    }

    func start(session: StoredSession, epoch: UInt64) async {
        let current = await isCurrent(session, epoch)
        guard enabled, current else { return }
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
            path: NetworkPathMonitor(), unauthorized: unauthorized, verification: verification)
        self.lifecycle = lifecycle
        attachedEpoch = epoch
        do { try await lifecycle.start() } catch {
            await lifecycle.stop()
            if self.generation == generation { self.lifecycle = nil }
        }
        if self.generation != generation { await lifecycle.stop() }
    }

    func resume(session: StoredSession, epoch: UInt64) async {
        guard await isCurrent(session, epoch) else { return }
        if attachedEpoch == epoch, let lifecycle {
            await lifecycle.requestSync()
        } else {
            await start(session: session, epoch: epoch)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        if !enabled { await stop() }
    }

    func requestSync() async { await lifecycle?.requestSync() }
    func refreshNow() async throws -> SyncResult? { try await lifecycle?.refreshNow() }
    func stop() async {
        generation &+= 1
        attachedEpoch = nil
        let previous = lifecycle
        lifecycle = nil
        await previous?.stop()
    }
}

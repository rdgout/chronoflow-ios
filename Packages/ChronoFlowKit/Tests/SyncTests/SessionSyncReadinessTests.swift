import AppCore
import Foundation
import LocalStore
import Sync
import Testing

private actor ReadinessCredentials: SessionStore {
    let data: Data
    init() throws { data = try JSONEncoder().encode(StoredSession(token: "test", accountId: syncAccount)) }
    func read() -> Data? { data }
    func write(_ data: Data) {}
    func delete() {}
}

private actor ReadinessControllerReference {
    var controller: SessionController?
    var resolved: SessionPresence?
    func set(_ controller: SessionController) { self.controller = controller }
    func resolve(_ presence: SessionPresence) { resolved = presence }
}

@Suite struct SessionSyncReadinessTests {
    @Test func routedTripUsesTheSessionStoreAndKeepsItsPlanAcrossSyncRestarts() async throws {
        let store = try await SyncStore()
        let accounts = SessionAccountDatabase(
            applicationSupport: store.root.appendingPathComponent("page"), namespace: .mock)
        try await accounts.open(accountID: AccountID(syncAccount))
        let database = try #require(await accounts.activeDatabase())
        let source = ScriptedSource()
        await source.configure(trips: [card(keep: false)])
        let clock = ManualSyncScheduler()
        let session = StoredSession(token: "test", accountId: syncAccount)
        let sync = SessionSync(
            accounts: accounts, scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }),
            source: { _ in source }, isCurrent: { value, epoch in value == session && epoch == 1 },
            unauthorized: { _ in }, verification: { _ in })
        await sync.start(session: session, epoch: 1)
        _ = try await sync.refreshNow()
        let repository = TripRepository(database: database)
        #expect(try await repository.plan(tripID: syncTrip, inputHash: "hash") == nil)
        let lease = sync.retention.hold(tripID: syncTrip)
        try await sync.fetchDetail(tripID: syncTrip, session: session, epoch: 1)
        #expect(try await repository.plan(tripID: syncTrip, inputHash: "hash") != nil)
        await sync.setEnabled(false)
        await sync.setEnabled(true)
        await sync.resume(session: session, epoch: 1)
        _ = try await sync.refreshNow()
        #expect(try await repository.plan(tripID: syncTrip, inputHash: "hash") != nil)
        await #expect(throws: CancellationError.self) {
            try await sync.fetchDetail(tripID: syncTrip, session: session, epoch: 2)
        }
        lease.release()
        _ = try await sync.refreshNow()
        #expect(try await repository.plan(tripID: syncTrip, inputHash: "hash") == nil)
        await sync.stop()
        try await accounts.close()
        try await store.close()
    }

    @Test func storedSessionResolvesWhileProductionSyncSourceStartupIsSuspended() async throws {
        let store = try await SyncStore()
        let accounts = SessionAccountDatabase(
            applicationSupport: store.root.appendingPathComponent("readiness"), namespace: .mock)
        let source = ScriptedSource()
        let startup = TestGate()
        let clock = ManualSyncScheduler()
        let sync = SessionSync(
            accounts: accounts, scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }),
            source: { _ in
                await startup.block()
                return source
            }, unauthorized: { _ in }, verification: { _ in })
        let reference = ReadinessControllerReference()
        let controller = SessionController(
            credentials: try ReadinessCredentials(), accounts: accounts, stopSync: { await sync.stop() },
            requestSync: { epoch in
                if let controller = await reference.controller {
                    await sync.requestStart(controller: controller, epoch: epoch)
                }
            })
        await reference.set(controller)
        let readiness = StoredDataReadiness(controller: controller) { _ in .init { $0.finish() } }
        let session = Task {
            let presence = await readiness.session()
            await reference.resolve(presence)
            return presence
        }
        await startup.waitUntilBlocked()
        let resolved = try await triggerEventually { await reference.resolved != nil }
        #expect(resolved)
        #expect(await reference.resolved == .signedIn(accountID: "019a562b-8000-7000-8000-000000000001"))
        #expect(await source.calls == [])
        await startup.release()
        #expect(await session.value == .signedIn(accountID: "019a562b-8000-7000-8000-000000000001"))
        await sync.stop()
        try await accounts.close()
        try await store.close()
    }
}

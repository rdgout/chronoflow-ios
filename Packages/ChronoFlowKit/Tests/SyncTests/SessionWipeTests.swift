import AppCore
import Foundation
import LocalStore
import Sync
import Testing

private actor WipeSessionStore: SessionStore {
    private(set) var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor WipeSyncHarness {
    let accounts: SessionAccountDatabase
    let source: ScriptedSource
    let clock = ManualSyncScheduler()
    var lifecycle: SyncLifecycle?
    private(set) var stopping = false
    init(accounts: SessionAccountDatabase, source: ScriptedSource) {
        self.accounts = accounts
        self.source = source
    }
    func start(_ generation: UInt64) async throws {
        let database = try #require(await accounts.activeDatabase())
        lifecycle = SyncLifecycle(
            database: database, source: source,
            epoch: SyncEpoch(accountID: try AccountID(syncAccount), generation: generation),
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await self.clock.sleep($0) }))
        try await lifecycle?.start()
    }
    func flush() async throws { _ = try await lifecycle?.refreshNow() }
    func stop() async {
        stopping = lifecycle != nil
        await lifecycle?.stop()
        lifecycle = nil
    }
}

@Suite struct SessionWipeTests {
    @Test func forcedWipeDrainsLateResponseBeforeCloseAndCannotRecreateFiles() async throws {
        let store = try await SyncStore()
        try await store.database.close()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let credentials = WipeSessionStore()
        let accounts = SessionAccountDatabase(applicationSupport: store.root, namespace: .api)
        let source = ScriptedSource()
        let harness = WipeSyncHarness(accounts: accounts, source: source)
        let wiper = AccountWiper(applicationSupport: store.root, namespace: .api, credentials: credentials)
        var hooks = SessionTeardown()
        hooks.beginWipe = { try await wiper.begin($0) }
        hooks.erase = { try await wiper.erase($0) }
        hooks.finishWipe = { try await wiper.finish() }
        hooks.logout = { _ in Issue.record("Forced 401 called logout") }
        let controller = SessionController(
            credentials: credentials, accounts: accounts, teardown: hooks,
            stopSync: { await harness.stop() }, requestSync: { try? await harness.start($0) })
        try await controller.accept(
            SessionResult(
                token: "test-token",
                account: SessionAccount(
                    id: syncAccount, name: "Local", email: "a@example.test", hasVerifiedEmail: true,
                    policies: syncPolicies, walkthroughSeen: true)))
        let database = try #require(await accounts.activeDatabase())
        let values = try await AccountRepository(database: database).values()
        let observer = Task {
            do { for try await _ in values { if Task.isCancelled { return } } } catch {}
        }
        let gate = TestGate()
        await source.configure(hook: { method in if method == "identity" { await gate.block() } })
        let refresh = Task { try await harness.flush() }
        await gate.waitUntilBlocked()
        let wipe = Task { try await controller.signOut(discardPending: true, unauthorized: true) }
        while !(await harness.stopping) { await Task.yield() }
        await gate.release()
        #expect(try await wipe.value == .signedOut)
        await #expect(throws: CancellationError.self) { try await refresh.value }
        await observer.value
        #expect(await credentials.data == nil)
        let directory = await database.directory(for: try AccountID(syncAccount))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        await #expect(throws: StoreFailure.closed) {
            try await database.write { db in try db.execute(sql: "UPDATE account SET name='late'") }
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

import AppCore
import DataAccess
import Foundation
import LocalStore
import PlanCore
import Settings
import Sync
import Testing

private let firstID = "019a562b-8000-7000-8000-000000000071"
private let secondID = "019a562b-8000-7000-8000-000000000072"

private actor Credentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor Gate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func block() async {
        entered = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }
    func wait() async {
        if entered { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct QuietClock: PlanClock {
    func values() async -> AsyncStream<Date> { AsyncStream { $0.finish() } }
}

@MainActor private struct Fixture {
    let root: URL
    let accounts: SessionAccountDatabase
    let credentials: Credentials
    let controller: SessionController
    let database: AccountDatabase
    let session: SessionSnapshot
    let model: SettingsHomeModel
    static func make(
        flush: @escaping @Sendable () async throws -> Void = { throw DataFailure.offline },
        logout: @escaping @Sendable (StoredSession) async throws -> Void = { _ in },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let credentials = Credentials()
        let wiper = AccountWiper(applicationSupport: root, namespace: .mock, credentials: credentials)
        var hooks = SessionTeardown()
        hooks.pendingCount = {
            guard let database = await accounts.activeDatabase() else { return 0 }
            return try await OutboxRepository(database: database).pending().count
        }
        hooks.flush = flush
        hooks.logout = logout
        hooks.sleep = sleep
        hooks.beginWipe = { try await wiper.begin($0) }
        hooks.erase = { try await wiper.erase($0) }
        hooks.finishWipe = { try await wiper.finish() }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: hooks)
        try await controller.accept(result(firstID))
        let database = try #require(await accounts.activeDatabase())
        let session = try #require(await controller.activeSession())
        let model = SettingsHomeModel(database: database, controller: controller, session: session, clock: QuietClock())
        model.start()
        return Self(
            root: root, accounts: accounts, credentials: credentials, controller: controller, database: database,
            session: session, model: model)
    }
    static func result(_ id: String) -> SessionResult {
        SessionResult(
            token: "token-\(id)",
            account: SessionAccount(
                id: id, name: "Account", email: "account@example.test", hasVerifiedEmail: true,
                policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
                walkthroughSeen: true))
    }
    func pending() async throws {
        try await TripRepository(database: database).upsert(
            TripRecord(id: "trip", card: JSONDocument("{}"), departureUtc: "2026-11-08T10:00:00Z"))
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(section: "planCredits", value: JSONDocument("{\"credits\":7}")))
        try await OutboxRepository(database: database).upsert(
            OutboxRecord(
                id: "pending", kind: "check-off",
                payload: .encoding(
                    CheckOffChange(
                        tripID: "trip", planInputHash: "hash", type: .sleep, localDate: "2026-11-08", ordinal: 0,
                        status: .done)), createdAt: "2026-11-08T10:00:00Z"))
    }
    func close() async throws {
        model.stop()
        try await accounts.close()
        try FileManager.default.removeItem(at: root)
    }
}

@Suite @MainActor struct SettingsHomeModelTests {
    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(await condition())
    }

    @Test func stayPreservesQueueDiscardWipesAndNextAccountHasNoOldRows() async throws {
        let f = try await Fixture.make()
        try await f.pending()
        await f.model.signOut()
        #expect(f.model.showsPending)
        #expect(f.model.confirmationCount == 1)
        #expect(f.model.state.pending.first?.category == .sleep)
        #expect(await f.credentials.data != nil)
        f.model.stay()
        #expect(!f.model.showsPending)
        #expect(await f.controller.activeSession() == f.session)
        #expect(try await OutboxRepository(database: f.database).pending().count == 1)
        await f.model.signOut()
        await f.model.signOut(discardPending: true)
        #expect(!f.model.showsPending)
        #expect(f.model.state.account == nil)
        #expect(await f.controller.presence == .signedOut)
        #expect(await f.credentials.data == nil)
        try await f.controller.accept(Fixture.result(secondID))
        let next = try #require(await f.accounts.activeDatabase())
        #expect(try await OutboxRepository(database: next).pending().isEmpty)
        #expect(try await TripRepository(database: next).trips().isEmpty)
        #expect(try await SettingsRepository(database: next).settings().allSatisfy { $0.section == "policies" })
        let old = f.root.appending(path: "\(StorageNamespace.mock.directoryName)/Accounts/\(firstID)")
        #expect(!FileManager.default.fileExists(atPath: old.path))
        try await f.close()
    }

    @Test func observationUpdatesBadgesAndEmptiedQueueDismissesSheet() async throws {
        let f = try await Fixture.make()
        try await f.pending()
        await f.model.signOut()
        #expect(f.model.showsPending)
        try await SettingsRepository(database: f.database).upsert(
            SettingsRecord(section: "planCredits", value: JSONDocument("{\"credits\":13}")))
        try await eventually { f.model.state.credits == 13 }
        try await OutboxRepository(database: f.database).remove(id: "pending")
        try await eventually { !f.model.showsPending && f.model.state.pending.isEmpty }
        try await f.close()
    }

    @Test func emptyQueueAndLogoutTimeoutStillFinishSignOut() async throws {
        let f = try await Fixture.make(
            logout: { _ in
                try await Task.sleep(for: .seconds(3600))
            },
            sleep: { seconds in
                #expect(seconds == 3)
            })
        await f.model.signOut()
        #expect(await f.controller.presence == .signedOut)
        #expect(!f.model.busy && !f.model.showsPending && f.model.failure == nil)
        #expect(await f.credentials.data == nil)
        try await f.close()
    }

    @Test func forced401DuringFlushNeverPresentsStaleConfirmation() async throws {
        let flush = Gate()
        let f = try await Fixture.make(flush: { await flush.block() })
        try await f.pending()
        let signOut = Task { await f.model.signOut() }
        await flush.wait()
        #expect(f.model.busy)
        let forced = Task { try await f.controller.unauthorized(epoch: f.session.epoch) }
        try await eventually { await f.controller.pendingUnauthorizedEpoch == f.session.epoch }
        await flush.release()
        await signOut.value
        #expect(try await forced.value == .signedOut)
        #expect(!f.model.showsPending && f.model.state.pending.isEmpty)
        #expect(await f.credentials.data == nil)
        try await f.close()
    }

    @Test func syncEventsDriveOfflineCopyAndReplayToALateSettingsSubscriber() async throws {
        let f = try await Fixture.make()
        let source = MockDataSource(offline: true)
        let sync = SessionSync(
            accounts: f.accounts, source: { _ in source }, unauthorized: { _ in }, verification: { _ in })
        let model = SettingsHomeModel(
            database: f.database, controller: f.controller, session: f.session, sync: sync, clock: QuietClock())
        model.start()
        await sync.start(session: f.session.session, epoch: f.session.epoch)
        try await eventually { model.offline && !model.syncing }
        let late = SettingsHomeModel(
            database: f.database, controller: f.controller, session: f.session, sync: sync, clock: QuietClock())
        late.start()
        try await eventually { late.offline && !late.syncing }
        #expect(
            late.state.syncCopy(now: late.now, syncing: late.syncing, offline: late.offline)?.key
                == "Saved on this phone · syncs when you're online")
        model.stop()
        late.stop()
        await sync.stop()
        try await f.close()
    }

    @Test func replacementSessionRevokesOldDiscardAndClearsValues() async throws {
        let f = try await Fixture.make()
        try await f.pending()
        await f.model.signOut()
        try await f.controller.accept(Fixture.result(secondID))
        let replacement = try #require(await f.controller.activeSession())
        await f.model.signOut(discardPending: true)
        #expect(await f.controller.activeSession() == replacement)
        try await eventually { f.model.state.account == nil && !f.model.showsPending }
        try await f.close()
    }
}

import AppCore
import Foundation
import GRDB
import Testing

@testable import LocalStore

private actor IntegrationCredentials: SessionStore {
    var data: Data?
    private var writeFails = false
    func read() -> Data? { data }
    func failWrites() { writeFails = true }
    func write(_ data: Data) throws {
        if writeFails { throw StoreFailure.unavailable }
        self.data = data
    }
    func delete() { data = nil }
}

private actor AccountDetachGate {
    private var armed = false
    private var entered = false
    private var released = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm() { armed = true }
    func waitIfArmed() async {
        guard armed else { return }
        armed = false
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        if !released { await withCheckedContinuation { releaseWaiter = $0 } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiter = $0 } }
    }
    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

struct SessionAccountDatabaseTests {
    @Test @MainActor func closeRejectsAnAttachmentResolvedBeforeDetachAndHidesTheClosingDatabase() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AccountModel()
        let gate = AccountDetachGate()
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock) {
            await model.detach()
            await gate.waitIfArmed()
        }
        try await accounts.open(accountID: AccountID(accountA))
        let first = try #require(await accounts.activeDatabase())
        let repository = AccountRepository(database: first)
        let a = AccountRecord(id: accountA, name: "A", email: "a")
        try await repository.upsert(a)
        await model.attach(to: repository, epoch: 1)
        await waitForModel(model, state: .loaded(a))
        let token = model.attachmentToken

        await gate.arm()
        let close = Task { try await accounts.close() }
        await gate.waitUntilEntered()
        #expect(model.state == .unknown)
        #expect(await accounts.activeDatabase() == nil)
        #expect(await first.accountID?.rawValue == accountA)
        await model.attach(to: repository, epoch: 99, ifCurrent: token)
        #expect(model.epoch == 1)
        #expect(model.state == .unknown)
        #expect(await first.observationCount == 0)
        await gate.release()
        try await close.value

        try await accounts.open(accountID: AccountID(accountB))
        let second = try #require(await accounts.activeDatabase())
        let b = AccountRecord(id: accountB, name: "B", email: "b")
        try await AccountRepository(database: second).upsert(b)
        await model.attach(to: AccountRepository(database: second), epoch: 2, ifCurrent: model.attachmentToken)
        await waitForModel(model, state: .loaded(b))
        await model.attach(to: repository, epoch: 99, ifCurrent: token)
        #expect(model.epoch == 2)
        #expect(model.state == .loaded(b))
        try await accounts.close()
        #expect(model.state == .unknown)
    }

    @Test(arguments: [accountA, accountB])
    func failedAcceptanceAfterSignInMatchesThePublishedStateAndDatabase(_ nextID: String) async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let credentials = IntegrationCredentials()
        let controller = SessionController(credentials: credentials, accounts: accounts)
        let account = SessionAccount(
            id: accountA, name: "A", email: "a@example.test", hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"), walkthroughSeen: false)
        try await controller.accept(SessionResult(token: "original", account: account))
        let first = try #require(await accounts.activeDatabase())
        var updates = await controller.updates().makeAsyncIterator()
        let published = try #require(await updates.next())
        await credentials.failWrites()
        let next = SessionAccount(
            id: nextID, name: "New", email: "new@example.test", hasVerifiedEmail: true,
            policies: account.policies, walkthroughSeen: false)
        await #expect(throws: SessionFailure.credentialWrite) {
            try await controller.accept(SessionResult(token: "replacement", account: next))
        }
        let persisted = try await credentials.readStoredSession()
        #expect(persisted == StoredSession(token: "original", accountId: accountA))
        let active = try #require(await accounts.activeDatabase())
        #expect(try await AccountRepository(database: active).account()?.id == nextID)
        if nextID == accountA {
            #expect(active === first)
            #expect(await controller.presence == published.presence)
            #expect(await controller.epoch == published.epoch)
            #expect(await controller.storedSession == persisted)
        } else {
            await #expect(throws: StoreFailure.closed) { try await AccountRepository(database: first).account() }
            #expect(await controller.storedSession == nil)
            try #require(await controller.presence == .signedOut)
            let update = try #require(await updates.next())
            #expect(update.presence == .signedOut)
            #expect(await controller.presence == update.presence)
            #expect(update.epoch == published.epoch + 1)
        }
        try await accounts.close()
    }

    @Test func acceptancePreservesSyncedMarkerAndAccountAndSourceIsolation() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for namespace in StorageNamespace.allCases {
            let accounts = SessionAccountDatabase(applicationSupport: root, namespace: namespace)
            let credentials = IntegrationCredentials()
            let controller = SessionController(credentials: credentials, accounts: accounts)
            let policies = AccountPolicies(termsVersion: "1", privacyVersion: "2")
            let a = SessionAccount(
                id: accountA, name: "A", email: "a@example.test", hasVerifiedEmail: false,
                policies: policies, walkthroughSeen: false)
            try await controller.accept(SessionResult(token: "test", account: a))
            let first = try #require(await accounts.activeDatabase())
            #expect(try await AccountRepository(database: first).account()?.syncedAt == nil)
            try await first.write { try $0.execute(sql: "UPDATE account SET synced_at=?", arguments: ["marker"]) }
            try await controller.accept(SessionResult(token: "new", account: a))
            #expect(try await AccountRepository(database: first).account()?.syncedAt == "marker")
            let settings = try await SettingsRepository(database: first).settings()
            #expect(try settings.first?.value.decode(AccountPolicies.self) == policies)
            let second = SessionAccount(
                id: accountB, name: "B", email: "b@example.test", hasVerifiedEmail: true,
                policies: policies, walkthroughSeen: true)
            try await controller.accept(SessionResult(token: "other", account: second))
            let active = try #require(await accounts.activeDatabase())
            #expect(try await AccountRepository(database: active).account()?.id == accountB)
            #expect(try await AccountRepository(database: active).account()?.syncedAt == nil)
            await #expect(throws: StoreFailure.closed) { try await AccountRepository(database: first).account() }
            await #expect(throws: StoreFailure.invalidAccountID) { try await accounts.upsert(a) }
            try await accounts.close()
            #expect(try await controller.restore() == .signedIn(accountID: accountB))
            try await accounts.close()
        }
    }
    @Test func devicePreferencesSurviveDeletingAllAccountFiles() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "net.chronoflow.tests.wipe-contract." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("nl", forKey: "language")
        defaults.set("dark", forKey: "appearance")
        let identity = try await DeviceIdentityStore(persistence: DevicePreferences(suiteName: suite)).identity()
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: accountA)
        let directory = await database.directory(for: try AccountID(accountA))
        try await database.close()
        try FileManager.default.removeItem(at: directory)
        let afterWipe = try await DeviceIdentityStore(persistence: DevicePreferences(suiteName: suite)).identity()
        #expect(afterWipe == identity)
        #expect(defaults.string(forKey: "language") == "nl")
        #expect(defaults.string(forKey: "appearance") == "dark")
    }

    @MainActor private func waitForModel(_ model: AccountModel, state: AccountModel.LoadState) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while model.state != state, ContinuousClock.now < deadline { await Task.yield() }
        #expect(model.state == state)
    }
}

import AppCore
import Foundation
import LocalStore
import PlanUI
import SnapshotSupport
import Sync
import Testing

@testable import DataAccess

private actor WalkthroughCredentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@MainActor private struct WalkthroughFixture {
    let root: URL
    let accounts: SessionAccountDatabase
    let controller: SessionController
    let credentials: WalkthroughCredentials
    let database: AccountDatabase
    let source: MockDataSource
    let result: SessionResult
    let epoch: SyncEpoch
    let permit: SessionMutationPermit

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let credentials = WalkthroughCredentials()
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let controller = SessionController(credentials: credentials, accounts: accounts)
        let source = MockDataSource(
            seed: try MockAppSeed.make(now: Date()), delay: { 0.3 }, sleep: { _ in })
        guard
            case .session(let result) = try await source.signIn(
                PasswordSignInInput(
                    email: MockScenarioValues.demoEmail, password: MockScenarioValues.password,
                    deviceID: "019a562b-8000-7000-8000-000000000099", deviceName: "Walkthrough test"))
        else { throw DataFailure.server(status: nil) }
        try await controller.accept(result)
        let snapshot = try #require(await controller.activeSession())
        let database = try #require(await accounts.activeDatabase())
        let permit = try #require(await controller.mutationPermit(for: snapshot))
        return Self(
            root: root, accounts: accounts, controller: controller, credentials: credentials, database: database,
            source: source, result: result,
            epoch: SyncEpoch(accountID: try AccountID(result.account.id), generation: snapshot.epoch), permit: permit)
    }

    func model() -> WalkthroughModel {
        WalkthroughModel { try await OutboxRepository(database: database).enqueue(.walkthrough, permit: permit) }
    }

    func gate() async throws -> Gate? {
        var iterator = try await AccountReadinessRepository(database: database).values(accountID: result.account.id)
            .makeAsyncIterator()
        return try await iterator.next()??.gate
    }

    func close() async throws {
        try await accounts.close()
        try FileManager.default.removeItem(at: root)
    }
}

@Suite @MainActor struct WalkthroughModelTests {
    @Test func nextNextDoneCommitsOnceAndGateMovesWithoutAnyNetworkRequest() async throws {
        let f = try await WalkthroughFixture.make()
        #expect(try await f.gate() == .walkthrough)
        await f.source.setOffline(true)
        let model = f.model()
        #expect(model.page == .timeline)
        await model.advance()
        #expect(model.page == .categories)
        await model.advance()
        #expect(model.page == .progress)
        #expect(try await OutboxRepository(database: f.database).pending().isEmpty)
        await model.advance()
        #expect(model.completed && !model.busy && model.failure == nil)
        #expect(try await f.gate() == .app)
        let rows = try await OutboxRepository(database: f.database).pending()
        #expect(rows.count == 1 && rows[0].kind == "walkthrough")
        #expect(try rows[0].change == .walkthrough)
        #expect(try await AccountRepository(database: f.database).account()?.walkthroughSeen == true)
        await model.skip()
        await model.advance()
        _ = try await OutboxRepository(database: f.database).enqueue(.walkthrough)
        #expect(try await OutboxRepository(database: f.database).pending().map(\.id) == rows.map(\.id))
        try await f.close()
    }

    @Test(arguments: WalkthroughModel.Page.allCases)
    func skipFromEveryPage(_ page: WalkthroughModel.Page) async throws {
        let f = try await WalkthroughFixture.make()
        let model = f.model()
        for _ in 0..<page.rawValue { await model.advance() }
        await model.skip()
        #expect(model.completed)
        #expect(try await f.gate() == .app)
        try await f.close()
    }

    @Test(arguments: [DataFailure.offline, .server(status: 503), .unauthorized(status: 401), .server(status: 422)])
    func failedFlushKeepsCompletionAndLaterSyncs(_ failure: DataFailure) async throws {
        let f = try await WalkthroughFixture.make()
        let model = f.model()
        await model.skip()
        await f.source.failNext(method: .send, error: failure)
        let engine = SyncEngine(database: f.database, source: f.source, epoch: f.epoch)
        let failed = try await engine.refreshNow()
        #expect(failed.state != .unauthorized)
        #expect(failed.pendingCount == 1)
        #expect(try await f.gate() == .app)
        #expect(await f.controller.activeSession() != nil)
        #expect(model.completed)
        #expect(try await OutboxRepository(database: f.database).pending().first?.attempts == 1)
        let retried = try await engine.refreshNow()
        #expect(retried.pendingCount == 0)
        #expect(try await f.source.fetchIdentity().walkthroughSeen)
        #expect(try await f.gate() == .app)
        await engine.cancelAndWait()
        try await f.close()
    }

    @Test func relaunchPendingOverlaySurvivesSessionUpsertAndStaleFullPull() async throws {
        let f = try await WalkthroughFixture.make()
        await f.model().skip()
        let pending = try await OutboxRepository(database: f.database).pending()
        try await f.accounts.close()
        let accounts = SessionAccountDatabase(applicationSupport: f.root, namespace: .mock)
        let restored = SessionController(credentials: f.credentials, accounts: accounts)
        #expect(try await restored.restore() == .signedIn(accountID: f.result.account.id))
        let database = try #require(await accounts.activeDatabase())
        try await accounts.upsert(f.result.account)
        let snapshot = try #require(await restored.activeSession())
        let epoch = SyncEpoch(accountID: try AccountID(f.result.account.id), generation: snapshot.epoch)
        _ = try await FullPull(database: database, source: f.source).run(epoch: epoch)
        #expect(try await OutboxRepository(database: database).pending().map(\.id) == pending.map(\.id))
        #expect(try await AccountRepository(database: database).account()?.walkthroughSeen == true)
        var iterator = try await AccountReadinessRepository(database: database).values(accountID: f.result.account.id)
            .makeAsyncIterator()
        let ready = try await iterator.next()
        #expect(ready??.gate == .app && ready??.firstLoadGate == .app)
        try await accounts.close()
        try FileManager.default.removeItem(at: f.root)
    }

    @Test func replayReturnsWithoutWritingOrRoutingToToday() async {
        var writes = 0
        var returns = 0
        let model = WalkthroughModel(mode: .replay, complete: { writes += 1 }, onFinish: { returns += 1 })
        await model.advance()
        await model.advance()
        await model.advance()
        await model.skip()
        #expect(model.completed && writes == 0 && returns == 1)
    }

    @Test func invalidatedSessionDoesNotCompleteAndStorageFailureCanRetry() async throws {
        let f = try await WalkthroughFixture.make()
        let model = f.model()
        try await f.controller.accept(f.result)
        await model.skip()
        #expect(!model.completed && !model.busy && model.failure != nil)
        #expect(try await f.gate() == .walkthrough)
        #expect(try await OutboxRepository(database: f.database).pending().isEmpty)
        var attempts = 0
        let retry = WalkthroughModel {
            attempts += 1
            if attempts == 1 { throw StoreFailure.unavailable }
            try await OutboxRepository(database: f.database).enqueue(.walkthrough)
        }
        await retry.skip()
        #expect(!retry.completed)
        await retry.skip()
        #expect(retry.completed && retry.failure == nil)
        try await f.close()
    }

    @Test func pendingLegacyRowOverridesAStaleFlagButKeepsVerificationAndTermsFirst() async throws {
        let f = try await WalkthroughFixture.make()
        await f.model().skip()
        var account = try #require(try await AccountRepository(database: f.database).account())
        account.walkthroughSeen = false
        try await AccountRepository(database: f.database).upsert(account)
        #expect(try await f.gate() == .app)
        account.hasVerifiedEmail = false
        try await AccountRepository(database: f.database).upsert(account)
        #expect(try await f.gate() == .verify)
        account.hasVerifiedEmail = true
        try await AccountRepository(database: f.database).upsert(account)
        try await SettingsRepository(database: f.database).upsert(
            SettingsRecord(
                section: "policies", value: .encoding(AccountPolicies(termsVersion: "new", privacyVersion: "1"))))
        #expect(try await f.gate() == .terms)
        try await f.close()
    }
}

@Suite struct WalkthroughGeometryTests {
    @Test func deviceTableUsesEveryInsetAndKeepsRoomForFixedControls() throws {
        let devices = try SnapshotDevice.all()
        #expect(Set(devices.map(\.alias)).isSuperset(of: ["se", "17e", "duo", "18promax"]))
        for device in devices {
            for insets in [device.insets, .init(top: 7, left: 19, bottom: 11, right: 31)] {
                let layout = WalkthroughGeometry(size: device.size, insets: insets)
                #expect(layout.content.minX == insets.left + 16)
                #expect(layout.content.maxX == device.width - insets.right - 16)
                #expect(layout.content.minY == insets.top + 8)
                #expect(layout.content.maxY == device.height - max(insets.bottom, 32))
                #expect(layout.content.height > 48 + 8 + 20 + 44)
            }
        }
    }
}

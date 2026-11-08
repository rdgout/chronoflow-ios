import AppCore
import Foundation
import LocalStore
import Settings
import Sync
import Testing

@testable import DataAccess

private actor TermsCredentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@MainActor private struct TermsFixture {
    let root: URL
    let accounts: SessionAccountDatabase
    let credentials: TermsCredentials
    let controller: SessionController
    let database: AccountDatabase
    let source: MockDataSource
    let result: SessionResult
    let session: SessionSnapshot
    let permit: SessionMutationPermit

    static func make(seen: Bool = false) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let credentials = TermsCredentials()
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let wiper = AccountWiper(applicationSupport: root, namespace: .mock, credentials: credentials)
        var teardown = SessionTeardown()
        teardown.pendingCount = {
            guard let database = await accounts.activeDatabase() else { return 0 }
            return try await OutboxRepository(database: database).pending().count
        }
        teardown.flush = { throw DataFailure.offline }
        teardown.beginWipe = { try await wiper.begin($0) }
        teardown.erase = { try await wiper.erase($0) }
        teardown.finishWipe = { try await wiper.finish() }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: teardown)
        let source = MockDataSource(
            seed: try MockAppSeed.make(now: Date(), walkthroughSeen: seen, termsPending: true),
            delay: { 0.3 }, sleep: { _ in })
        guard
            case .session(let result) = try await source.signIn(
                PasswordSignInInput(
                    email: MockScenarioValues.demoEmail, password: MockScenarioValues.password,
                    deviceID: "019a562b-8000-7000-8000-000000000099", deviceName: "Terms test"))
        else { throw DataFailure.server(status: nil) }
        try await controller.accept(result)
        let session = try #require(await controller.activeSession())
        let database = try #require(await accounts.activeDatabase())
        let permit = try #require(await controller.mutationPermit(for: session))
        return Self(
            root: root, accounts: accounts, credentials: credentials, controller: controller,
            database: database, source: source, result: result, session: session, permit: permit)
    }

    func model() -> TermsUpdateModel {
        TermsUpdateModel(policies: result.account.policies) { version in
            try await OutboxRepository(database: database).enqueue(.policies(version: version), permit: permit)
        }
    }

    func gate() async throws -> Gate? {
        try await Self.gate(database, accountID: result.account.id)
    }

    static func gate(_ database: AccountDatabase, accountID: String) async throws -> Gate? {
        var iterator = try await AccountReadinessRepository(database: database).values(accountID: accountID)
            .makeAsyncIterator()
        return try await iterator.next()??.gate
    }

    func close() async throws {
        try await accounts.close()
        try FileManager.default.removeItem(at: root)
    }
}

@Suite @MainActor struct TermsAcceptanceTests {
    @Test(arguments: [false, true])
    func offlineAcceptanceOpensNextGateAndCanSyncLater(_ seen: Bool) async throws {
        let f = try await TermsFixture.make(seen: seen)
        #expect(try await f.gate() == .terms)
        await f.source.setOffline(true)
        let model = f.model()
        await model.accept()
        #expect(model.completed && !model.failed && !model.busy)
        #expect(try await f.gate() == (seen ? .app : .walkthrough))
        let rows = try await OutboxRepository(database: f.database).pending()
        #expect(rows.count == 1 && rows[0].kind == "settings")
        #expect(try rows[0].change == .policies(version: f.result.account.policies.termsVersion))
        await model.accept()
        _ = try await OutboxRepository(database: f.database).enqueue(
            .policies(version: f.result.account.policies.termsVersion))
        #expect(try await OutboxRepository(database: f.database).pending().map(\.id) == rows.map(\.id))
        let epoch = SyncEpoch(accountID: try AccountID(f.result.account.id), generation: f.session.epoch)
        let flush = OutboxFlusher(database: f.database, source: f.source)
        #expect(try await flush.run(epoch: epoch).offline)
        #expect(try await f.gate() == (seen ? .app : .walkthrough))
        await f.source.setOffline(false)
        _ = try await flush.run(epoch: epoch)
        #expect(try await OutboxRepository(database: f.database).pending().isEmpty)
        #expect(
            try await f.source.fetchIdentity().policies.acceptedTermsVersion == f.result.account.policies.termsVersion)
        if !seen {
            _ = try await OutboxRepository(database: f.database).enqueue(.walkthrough, permit: f.permit)
            #expect(try await f.gate() == .app)
        }
        try await f.close()
    }

    @Test func relaunchSessionUpsertAndStaleFullPullKeepPendingAcceptance() async throws {
        let f = try await TermsFixture.make()
        await f.model().accept()
        let rows = try await OutboxRepository(database: f.database).pending()
        try await f.accounts.close()
        let accounts = SessionAccountDatabase(applicationSupport: f.root, namespace: .mock)
        let restored = SessionController(credentials: f.credentials, accounts: accounts)
        #expect(try await restored.restore() == .signedIn(accountID: f.result.account.id))
        let database = try #require(await accounts.activeDatabase())
        #expect(try await TermsFixture.gate(database, accountID: f.result.account.id) == .walkthrough)
        try await accounts.upsert(f.result.account)
        let snapshot = try #require(await restored.activeSession())
        let epoch = SyncEpoch(accountID: try AccountID(f.result.account.id), generation: snapshot.epoch)
        _ = try await FullPull(database: database, source: f.source).run(epoch: epoch)
        #expect(try await TermsFixture.gate(database, accountID: f.result.account.id) == .walkthrough)
        #expect(try await OutboxRepository(database: database).pending().map(\.id) == rows.map(\.id))
        try await accounts.close()
        try FileManager.default.removeItem(at: f.root)
    }

    @Test func failedOutboxInsertRollsBackAcceptanceAndShowsRetry() async throws {
        let f = try await TermsFixture.make()
        try await f.database.write {
            try $0.execute(
                sql: "CREATE TRIGGER fail_terms BEFORE INSERT ON outbox BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        }
        let model = f.model()
        await model.accept()
        #expect(model.failed && !model.completed && model.canAccept)
        #expect(try await f.gate() == .terms)
        #expect(try await OutboxRepository(database: f.database).pending().isEmpty)
        try await f.database.write { try $0.execute(sql: "DROP TRIGGER fail_terms") }
        await model.accept()
        #expect(model.completed && !model.failed)
        #expect(try await f.gate() == .walkthrough)
        try await f.close()
    }

    @Test func newerServerVersionStillRequiresAcceptanceAndRejectsStaleScreen() async throws {
        let f = try await TermsFixture.make()
        let stale = f.model()
        await f.model().accept()
        try await f.accounts.upsert(
            SessionAccount(
                id: f.result.account.id, name: "Name", email: f.result.account.email, hasVerifiedEmail: true,
                policies: AccountPolicies(termsVersion: "new", privacyVersion: "new"), walkthroughSeen: false))
        #expect(try await f.gate() == .terms)
        await stale.accept()
        #expect(stale.failed && !stale.completed)
        let pending = try await OutboxRepository(database: f.database).pending()
        #expect(pending.count == 1)
        let current = TermsUpdateModel(policies: AccountPolicies(termsVersion: "new", privacyVersion: "new")) {
            try await OutboxRepository(database: f.database).enqueue(.policies(version: $0), permit: f.permit)
        }
        await current.accept()
        #expect(current.completed)
        #expect(try await f.gate() == .walkthrough)
        try await f.close()
    }

    @Test func revokedPermitCannotAcceptForAnotherSession() async throws {
        let f = try await TermsFixture.make()
        let model = f.model()
        _ = try await f.controller.signOut(discardPending: true)
        await model.accept()
        #expect(!model.completed)
        #expect(await f.controller.activeSession() == nil)
        try await f.close()
    }

    @Test func signOutFromTermsUsesExistingPendingConfirmationStayAndDiscard() async throws {
        let f = try await TermsFixture.make()
        let model = SettingsHomeModel(database: f.database, controller: f.controller, session: f.session)
        _ = try await OutboxRepository(database: f.database).enqueue(
            .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])), permit: f.permit)
        await model.signOut()
        #expect(model.showsPending && model.confirmationCount == 1)
        #expect(await f.controller.activeSession() == f.session)
        model.stay()
        #expect(!model.showsPending)
        await model.signOut()
        await model.signOut(discardPending: true)
        #expect(await f.controller.activeSession() == nil)
        try await f.close()
    }
}

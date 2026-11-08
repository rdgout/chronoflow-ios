import Foundation
import LocalStore
import Settings
import Sync
import Testing

@testable import AppCore
@testable import DataAccess

struct SettingsPageFixture {
    let root: URL
    let database: AccountDatabase
    let permit = SessionMutationPermit()
    let id = "019a562b-8000-7000-8000-000000000091"
    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let database = AccountDatabase(applicationSupport: root, namespace: .mock)
        let fixture = Self(root: root, database: database)
        try await database.open(accountID: fixture.id)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: fixture.id, name: "Original", email: "demo@example.com"))
        return fixture
    }
    @MainActor func model() -> SettingsPagesModel {
        SettingsPagesModel(database: database, permit: permit, isCurrent: { true })
    }
    func close() async throws {
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }
}

@Suite @MainActor struct SettingsProfileTests {
    @Test func validatesTrimsAndPreservesEditedDraftDuringPulls() async {
        var writes: [String] = []
        let account = AccountRecord(id: "account", name: "Original", email: "demo@example.com")
        let model = SettingsProfileModel(account: account) { writes.append($0) }
        model.name = " \n "
        await model.submit()
        #expect(model.errorKey == "Enter your name.")
        #expect(writes.isEmpty)
        model.name = "  My draft  "
        var remote = account
        remote.name = "Other device"
        model.receive(remote)
        #expect(model.name == "  My draft  ")
        await model.submit()
        #expect(writes == ["My draft"])
        #expect(model.name == "My draft" && model.saved && model.errorKey == nil)
    }

    @Test func sessionUpsertPreservesPendingProfileAcrossRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let id = try AccountID("019a562b-8000-7000-8000-000000000092")
        let account = SessionAccount(
            id: id.rawValue, name: "Original", email: "demo@example.com", hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
            walkthroughSeen: true)
        try await accounts.open(accountID: id)
        try await accounts.upsert(account)
        let database = try #require(await accounts.activeDatabase())
        try await OutboxRepository(database: database).enqueue(
            .profile(ProfileChange(name: "Pending", email: account.email)))
        try await accounts.close()
        try await accounts.open(accountID: id)
        try await accounts.upsert(account)
        let reopened = try #require(await accounts.activeDatabase())
        #expect(try await AccountRepository(database: reopened).account()?.name == "Pending")
        try await accounts.close()
        try FileManager.default.removeItem(at: root)
    }

    @Test func storageFailureKeepsDraftForRetry() async {
        let model = SettingsProfileModel(account: AccountRecord(id: "id", name: "Name", email: "e")) { _ in
            throw StoreFailure.closed
        }
        model.name = "Edited"
        await model.submit()
        #expect(!model.saved && !model.busy)
        #expect(model.name == "Edited")
        #expect(model.errorKey == "We couldn't save your change. Please try again.")
    }

    @Test func offlineProfileIsDurablePendingPullCannotOverwriteAndRevokedPermitCannotWrite() async throws {
        let f = try await SettingsPageFixture.make()
        let account = try #require(try await AccountRepository(database: f.database).account())
        let model = SettingsProfileModel(account: account) { name in
            try await OutboxRepository(database: f.database).enqueue(
                .profile(ProfileChange(name: name, email: account.email)), permit: f.permit)
        }
        model.name = "Saved offline"
        await model.submit()
        #expect(model.saved)
        let epoch = SyncEpoch(accountID: try AccountID(f.id), generation: 0)
        let result = try await OutboxFlusher(database: f.database, source: MockDataSource(offline: true)).run(
            epoch: epoch)
        #expect(result.offline)
        #expect(try await OutboxRepository(database: f.database).pending().count == 1)
        let identity = AccountIdentity(
            id: f.id, name: "Old server name", email: account.email, hasVerifiedEmail: true,
            policies: AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1"),
            walkthroughSeen: true)
        try await f.database.write { db in try StoreApplication.identity(identity, accountID: AccountID(f.id), db: db) }
        #expect(try await AccountRepository(database: f.database).account()?.name == "Saved offline")
        f.permit.invalidate()
        model.name = "Stale session"
        await model.submit()
        #expect(!model.saved)
        #expect(try await AccountRepository(database: f.database).account()?.name == "Saved offline")
        try await f.close()
    }
}

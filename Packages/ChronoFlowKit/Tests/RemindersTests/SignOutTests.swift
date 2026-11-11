import AppCore
import Foundation
import LocalStore
import Testing

@testable import Reminders

private actor ReminderCredentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@Suite struct ReminderSignOutTests {
    @Test func signOutWipesNotificationsLedgerAndAccountDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let center = FakeReminderCenter()
        let service = ReminderService(center: center, now: { reminderNow })
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock) { await service.detach() }
        let credentials = ReminderCredentials()
        let wiper = AccountWiper(applicationSupport: root, namespace: .mock, credentials: credentials)
        var teardown = SessionTeardown()
        teardown.beginWipe = { try await wiper.begin($0) }
        teardown.erase = { try await wiper.erase($0) }
        teardown.finishWipe = { try await wiper.finish() }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: teardown)
        let result = SessionResult(
            token: "test",
            account: SessionAccount(
                id: reminderAccount, name: "Demo", email: "demo@example.com",
                hasVerifiedEmail: true, policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"),
                walkthroughSeen: true))
        try await controller.accept(result)
        let snapshot = try #require(await controller.activeSession())
        let database = try #require(await accounts.activeDatabase())
        let fixture = try await ReminderTestStore()
        try await fixture.store(reminderPlan())
        let trip = try #require(try await TripRepository(database: fixture.database).trips().first)
        let version = try #require(
            try await TripRepository(database: fixture.database).plan(tripID: trip.id, inputHash: "hash"))
        try await TripRepository(database: database).upsert(trip)
        try await TripRepository(database: database).store(plan: version, checks: [])
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        await service.attach(database: database)
        try await eventually { await center.pending().count == 1 }
        let directory = await database.directory(for: try AccountID(reminderAccount))
        #expect(!(try await ReminderLedger.read(database: database)).isEmpty)
        #expect(try await controller.signOut(expected: snapshot, discardPending: true) == .signedOut)
        #expect(await center.pending().isEmpty)
        #expect(await accounts.activeDatabase() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await credentials.read() == nil)
        try await fixture.close()
        try FileManager.default.removeItem(at: root)
    }
}

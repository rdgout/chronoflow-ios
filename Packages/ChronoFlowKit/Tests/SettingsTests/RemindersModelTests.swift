import AppCore
import Foundation
import LocalStore
import Reminders
import Settings
import Testing

@testable import DataAccess

private actor ReminderModelCredentials: SessionStore {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@Suite @MainActor struct RemindersModelTests {
    @Test func settingsOutboxPendingProtectionPermissionReturnAndRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        let controller = SessionController(credentials: ReminderModelCredentials(), accounts: accounts)
        let source = MockDataSource(seed: try MockAppSeed.make(now: Date()), delay: { 0 }, sleep: { _ in })
        guard
            case .session(let result) = try await source.signIn(
                PasswordSignInInput(
                    email: MockScenarioValues.demoEmail,
                    password: MockScenarioValues.password, deviceID: "019a562b-8000-7000-8000-000000000099",
                    deviceName: "Reminders"))
        else { throw DataFailure.offline }
        try await controller.accept(result)
        let snapshot = try #require(await controller.activeSession())
        let permit = try #require(await controller.mutationPermit(for: snapshot))
        let database = try #require(await accounts.activeDatabase())
        let repository = SettingsRepository(database: database)
        try await repository.upsert(SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        let center = MockReminderCenter(permission: .granted)
        let service = ReminderService(center: center)
        let model = RemindersModel(database: database, permit: permit, service: service)
        await model.start()
        #expect(model.active)
        await model.setEnabled(false)
        await model.setLead(60)
        let rows = try await OutboxRepository(database: database).pending()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.kind == "settings" && $0.dependency == "settings:reminders" })
        try await database.write { db in
            try StoreApplication.setting("reminders", value: .encoding(ReminderSettings()), db: db)
        }
        let local = try #require(try await repository.settings().first { $0.section == "reminders" }).value.decode(
            ReminderSettings.self)
        #expect(!local.enabled)
        #expect(local.leadMin == 60)
        model.stop()
        let relaunched = RemindersModel(database: database, permit: permit, service: service)
        await relaunched.start()
        #expect(!relaunched.active)
        #expect(relaunched.settings?.leadMin == 60)
        await center.setStatus(.blocked)
        await relaunched.refreshPermission()
        #expect(relaunched.permission == .blocked)
        await center.setStatus(.granted)
        await relaunched.refreshPermission()
        let enabled = try #require(try await repository.settings().first { $0.section == "reminders" }).value.decode(
            ReminderSettings.self)
        #expect(enabled.enabled)
        #expect(enabled.leadMin == 60)
        relaunched.stop()
        _ = try await controller.signOut(expected: snapshot, discardPending: true)
        await relaunched.setEnabled(false)
        #expect(relaunched.failure != nil)
        try FileManager.default.removeItem(at: root)
    }
}

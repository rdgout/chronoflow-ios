import AppCore
import Foundation
import LocalStore
import Sync
import Testing
import TripWizard

@testable import DataAccess

@Suite struct WizardGenerationSessionTests {
    @Test func reviewEffectsRequireTheOriginalSessionPermitThroughCommit() async throws {
        let source = MockDataSource(delay: { 0 }, sleep: { _ in })
        guard
            case .session(let result) = try await source.signIn(
                PasswordSignInInput(
                    email: MockScenarioValues.demoEmail, password: MockScenarioValues.password,
                    deviceID: "019a562b-8000-7000-8000-000000000099", deviceName: "Wizard test"))
        else { throw DataFailure.server(status: nil) }
        let controller = SessionController(credentials: WizardCredentials(), accounts: WizardAccounts())
        try await controller.accept(result)
        let snapshot = try #require(await controller.activeSession())
        let permit = try #require(await controller.mutationPermit(for: snapshot))
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let database = AccountDatabase(applicationSupport: directory, namespace: .mock)
        try await database.open(accountID: snapshot.session.accountId)
        let epoch = SyncEpoch(accountID: try AccountID(snapshot.session.accountId), generation: snapshot.epoch)
        let effects = TripGenerationEffects.storing(
            database: database, source: source, epoch: epoch, permit: permit, requestSync: {})
        try await effects.mergeProfile(JSONObject(["habitual_bed": .string("23:30")]))
        _ = try await controller.signOut(discardPending: true)
        await #expect(throws: CancellationError.self) {
            try await effects.mergeProfile(JSONObject(["habitual_bed": .string("21:00")]))
        }
        let body = try #require(
            try await SettingsRepository(database: database).settings().first { $0.section == "bodyClock" })
        #expect(try body.value.decode(JSONObject.self)["habitualBed"] == .string("23:30"))
        try await database.close()
        try FileManager.default.removeItem(at: directory)
    }
}

private actor WizardCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor WizardAccounts: SessionAccountStore {
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) {}
    func close() {}
}

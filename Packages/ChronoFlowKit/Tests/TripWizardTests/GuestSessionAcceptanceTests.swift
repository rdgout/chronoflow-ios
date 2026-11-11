import AppCore
import Auth
import Foundation
import LocalStore
import Testing
import TripWizard

@MainActor struct GuestSessionAcceptanceTests {
    @Test(arguments: [AuthenticationMethod.signUp, .password, .passkey])
    func claimedTripSurvivesEveryGateAndIsConsumedOnce(_ method: AuthenticationMethod) async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.seedGuest()
        let result = fixture.result(tripID: "guest-token", verified: false, accepted: false, seen: false)
        try await fixture.controller.accept(result)
        let navigator = GuestAcceptanceNavigator()
        try await fixture.acceptance.routeAcceptedSession(
            result, method: method, controller: fixture.controller, accounts: fixture.accounts,
            readiness: fixture.readiness, navigator: navigator,
            verification: { _ in navigator.navigate(to: .verify) })
        #expect(navigator.routes == [.verify])
        #expect(try await fixture.guest.recover() == nil)
        #expect(await fixture.secrets.get(for: "guest-token") == nil)
        for gate in [Gate.verify, .terms, .walkthrough, .app] {
            let account = fixture.result(
                verified: gate != .verify, accepted: gate == .walkthrough || gate == .app, seen: gate == .app
            ).account
            try await fixture.accounts.upsert(account)
            #expect(AuthNavigation.route(for: account) == gate.route)
            await fixture.readiness.routeAcceptedSession(navigator: navigator) { _ in
                navigator.navigate(to: .verify)
            }
            #expect(navigator.routes.last == gate.route)
            let repository = try await fixture.continuation()
            #expect(try await repository.consume(gate: gate) == (gate == .app ? .trip("guest-token") : nil))
        }
        #expect(try await fixture.continuation().consume(gate: .app) == nil)
        try await fixture.accounts.close()
    }

    @Test(arguments: [AuthenticationMethod.password, .passkey])
    func loginWithoutTripSeedsOnlyJourneyIntoTheAccountWizard(_ method: AuthenticationMethod) async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let guest = try await fixture.seedGuest()
        let result = fixture.result()
        try await fixture.controller.accept(result)
        let database = try #require(await fixture.accounts.activeDatabase())
        let settings = SettingsRepository(database: database)
        let bodyClock = JSONObject(["habitualBed": .string("21:00"), "habitualWake": .string("05:00")])
        try await settings.upsert(SettingsRecord(section: "bodyClock", value: .encoding(bodyClock)))
        try await settings.upsert(SettingsRecord(section: "sleepAnswered", value: .encoding(true)))
        let savedSettings = try await settings.settings()
        let bodyClockRecord = try #require(savedSettings.first { $0.section == "bodyClock" })
        let savedBodyClock = try bodyClockRecord.value.decode(JSONObject.self)
        let store = MemberWizardStore(database: database)
        let replaced = try await store.start()
        try await fixture.acceptance.accept(result, method: method, database: database)
        let seeded = try #require(await store.recover())
        var expected = guest.form
        expected.identity = nil
        expected.override = WizardSleepOverride()
        #expect(seeded.form == expected && seeded.airports == guest.airports)
        #expect(seeded.state.mode == .member && seeded.state.step == .checking && seeded.state.returnToReady == true)
        #expect(seeded.state.entered && !seeded.state.fromLastTrip && seeded.state.profile == JSONObject())
        #expect(seeded.state.review == nil && seeded.state.questions == nil && seeded.state.checkedInput == nil)
        #expect(seeded.state.reviewedAt == nil && seeded.state.checkingAnswers == nil && seeded.fieldErrors.isEmpty)
        #expect(seeded.state.savedProfile == savedBodyClock && !seeded.state.sleepNeeded)
        #expect(seeded.state.instance != guest.state.instance && seeded.state.instance != replaced.state.instance)
        await #expect(throws: CancellationError.self) { try await store.persist(replaced) }
        #expect(try await fixture.guest.recover() == nil)
        #expect(await fixture.secrets.get(for: "guest-token") == nil)
        #expect(try await fixture.continuation().consume(gate: .app) == .memberWizard)
        #expect(try await DraftRepository(database: database).drafts().isEmpty)
        #expect(try await settings.settings() == savedSettings)
        try await fixture.accounts.close()
    }

    @Test func twoFactorDropsTheGuestAndContinuesToMyTripsWithoutSeeding() async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.seedGuest()
        let result = fixture.result()
        try await fixture.controller.accept(result)
        let database = try #require(await fixture.accounts.activeDatabase())
        try await fixture.acceptance.accept(result, method: .twoFactor, database: database)
        #expect(try await MemberWizardStore(database: database).recover() == nil)
        #expect(try await fixture.guest.recover() == nil)
        #expect(await fixture.secrets.get(for: "guest-token") == nil)
        #expect(try await fixture.continuation().consume(gate: .app) == .trips)
        #expect(try await fixture.continuation().consume(gate: .app) == nil)
        try await fixture.accounts.close()
    }

    @Test(arguments: [AuthenticationMethod.signUp, .password, .passkey, .twoFactor])
    func ordinaryAuthenticationKeepsTheMemberWizard(_ method: AuthenticationMethod) async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let result = fixture.result()
        try await fixture.controller.accept(result)
        let database = try #require(await fixture.accounts.activeDatabase())
        let store = MemberWizardStore(database: database)
        let before = try await store.start()
        try await fixture.acceptance.accept(result, method: method, database: database)
        #expect(try await store.recover() == before)
        #expect(try await fixture.continuation().consume(gate: .app) == nil)
        try await fixture.accounts.close()
    }

    @Test func continuationPersistsOnReopenAndSignOutErasesIt() async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.seedGuest()
        let result = fixture.result(tripID: "guest-token")
        try await fixture.controller.accept(result)
        let database = try #require(await fixture.accounts.activeDatabase())
        try await fixture.acceptance.accept(result, method: .signUp, database: database)
        try await fixture.accounts.close()
        try await fixture.accounts.open(accountID: AccountID(result.account.id))
        let restored = try await fixture.continuation()
        var values = try await restored.values().makeAsyncIterator()
        #expect(try await values.next() == .some(.trip("guest-token")))
        #expect(try await fixture.controller.signOut(discardPending: true) == .signedOut)
        try await fixture.accounts.open(accountID: AccountID(result.account.id))
        #expect(try await fixture.continuation().consume(gate: .app) == nil)
        #expect(try await fixture.guest.recover() == nil)
        #expect(await fixture.secrets.get(for: "guest-token") == nil)
        try await fixture.accounts.close()
    }

    @Test func anotherAccountCannotTakeTheGuestOrItsContinuation() async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let guest = try await fixture.seedGuest()
        let result = fixture.result(tripID: "guest-token")
        let other = AccountDatabase(applicationSupport: fixture.root, namespace: .mock)
        try await other.open(accountID: "019a562b-8000-7000-8000-000000000002")
        await #expect(throws: CancellationError.self) {
            try await fixture.acceptance.accept(result, method: .password, database: other)
        }
        #expect(try await fixture.guest.recover() == guest)
        #expect(try await GuestContinuationRepository(database: other).consume(gate: .app) == nil)
        #expect(await fixture.secrets.get(for: "guest-token") == "secret")
        try await other.close()
    }

    @Test func committedSessionFinishesContinuationAfterRequestCancellation() async throws {
        let fixture = GuestAcceptanceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.seedGuest()
        let result = fixture.result(tripID: "guest-token")
        try await fixture.controller.accept(result)
        let navigator = GuestAcceptanceNavigator()
        try await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await fixture.acceptance.routeAcceptedSession(
                result, method: .signUp, controller: fixture.controller, accounts: fixture.accounts,
                readiness: fixture.readiness, navigator: navigator,
                verification: { _ in Issue.record("Unexpected verification") })
        }.value
        #expect(navigator.routes == [.today])
        #expect(try await fixture.continuation().consume(gate: .app) == .trip("guest-token"))
        #expect(try await fixture.guest.recover() == nil)
        try await fixture.accounts.close()
    }
}

private struct GuestAcceptanceFixture {
    let root = guestStoreTestDirectory()
    let secrets = MemoryGuestSecretStore()
    let credentials = GuestAcceptanceCredentials()
    let accounts: SessionAccountDatabase
    let guest: GuestWizardStore
    let controller: SessionController
    let readiness: StoredDataReadiness
    var acceptance: GuestSessionAcceptance { GuestSessionAcceptance(guest: guest, secrets: secrets) }

    init() {
        guest = GuestWizardStore(applicationSupport: root, namespace: .mock)
        let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
        self.accounts = accounts
        let wiper = AccountWiper(
            applicationSupport: root, namespace: .mock, credentials: credentials, guestSecrets: secrets)
        var teardown = SessionTeardown()
        teardown.beginWipe = { try await wiper.begin($0) }
        teardown.erase = { try await wiper.erase($0) }
        teardown.finishWipe = { try await wiper.finish() }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: teardown)
        self.controller = controller
        readiness = StoredDataReadiness(controller: controller) { id in
            guard let database = await accounts.activeDatabase() else { throw StoreFailure.closed }
            return try await AccountReadinessRepository(database: database).values(accountID: id)
        }
    }

    func result(tripID: String? = nil, verified: Bool = true, accepted: Bool = true, seen: Bool = true) -> SessionResult
    {
        SessionResult(
            token: "session-token",
            account: SessionAccount(
                id: "019a562b-8000-7000-8000-000000000001", name: "Traveller", email: "test@example.com",
                hasVerifiedEmail: verified,
                policies: AccountPolicies(
                    termsVersion: "2", privacyVersion: "2", acceptedTermsVersion: accepted ? "2" : nil),
                walkthroughSeen: seen), tripId: tripID)
    }

    @discardableResult func seedGuest() async throws -> MemberWizardDraft {
        var draft = try await guest.start()
        draft.form.legs[0].fromIata = "AMS"
        draft.form.legs[0].toIata = "HND"
        draft.form.legs[0].departLocal = "2027-03-28T12:00"
        draft.form.legs[0].arriveLocal = "2027-03-29T09:00"
        draft.form.preparation.days = 2
        draft.form.identity = ApiReviewIdentity(token: "guest-token", inputRevision: 4, reviewRevision: 7)
        draft.form.override.enabled = true
        draft.form.override.habitualBed = "22:00"
        draft.state.profile["age_band"] = .string("65_plus")
        draft.state.profile["shift_work"] = .bool(false)
        draft.state.step = .ready
        draft.state.checkedInput = Data([1])
        draft.state.reviewedAt = Date()
        draft.airports["AMS"] = wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam")
        try await guest.persist(draft)
        await secrets.set("secret", for: "guest-token")
        return draft
    }

    func continuation() async throws -> GuestContinuationRepository {
        let database = try #require(await accounts.activeDatabase())
        return GuestContinuationRepository(database: database)
    }
}

private actor GuestAcceptanceCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

@MainActor private final class GuestAcceptanceNavigator: Navigator {
    var routes: [Route] = []
    func navigate(to route: Route) { routes.append(route) }
}

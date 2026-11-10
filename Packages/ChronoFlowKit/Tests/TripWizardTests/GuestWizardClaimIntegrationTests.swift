import AppCore
import Auth
import DataAccess
import Foundation
import LocalStore
import Testing
import TripWizard

@Suite @MainActor struct GuestWizardClaimIntegrationTests {
    @Test(arguments: [AuthLanguage.en, .nl])
    func guestJourneyClaimsTheReviewedTripAndWaitsForTheAccountGates(_ language: AuthLanguage) async throws {
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = MockDataSource(seed: MockServerState(), now: { now }, delay: { 0 })
        let secrets = MemoryGuestSecretStore()
        let device = DeviceIdentityStore(persistence: GuestJourneyDevice())
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock, now: { now })
        var draft = try await store.start()
        draft.state.profile["chronotype"] = .string("intermediate")
        draft.state.profile["shift_work"] = .bool(false)
        let clock = CheckingTestClock()
        let model = MemberWizardModel(
            draft: draft, store: store, search: AirportSearchService(source: source), now: { now },
            generation: GuestWizardGeneration(source: source, secrets: secrets, deviceIdentity: device),
            checkingClock: clock.clock)
        model.chooseAirport(
            wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            sheet: WizardAirportSheet(index: 0, side: .from))
        model.chooseAirport(
            wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"),
            sheet: WizardAirportSheet(index: 0, side: .to))
        model.finishRoute()
        #expect(model.draft.state.step == .outbound)
        model.setDateTime("2030-10-12T14:40", index: 0, arrival: false)
        model.setDateTime("2030-10-13T09:15", index: 0, arrival: true)
        #expect(model.finishOutbound())
        model.finishOutboundStep()
        #expect(model.draft.state.step == .sleep)
        #expect(model.finishSleep())
        try await finishChecking(model, clock: clock, start: 0)
        #expect(model.currentQuestion?.fields == ["age_band"])
        model.answerQuestion(.string("18_64"))
        try await waitFor { clock.deadlines.contains(1.75) }
        clock.advance(to: 1.75)
        try await finishChecking(model, clock: clock, start: 1.75)
        #expect(model.draft.state.step == .fineTune)
        #expect(model.optionalPrompts.isEmpty)
        model.finishFineTune()
        #expect(model.draft.state.step == .ready)
        model.savePlan()
        #expect(model.saveOutcome == .signUpRequested && model.createdTripID == nil)
        await model.flush()
        let token = try #require(model.draft.form.identity?.token)
        let database = AccountDatabase(applicationSupport: root, namespace: .mock)
        var accepted: SessionResult?
        let signup = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { try await device.identity() },
            deviceName: "iPhone", claim: { await store.claim(secrets: secrets) },
            accept: { result in
                try await database.open(accountID: result.account.id)
                try await GuestSessionAcceptance(guest: store, secrets: secrets).accept(
                    result, method: .signUp, database: database)
                accepted = result
            })
        signup.editName("Traveller")
        signup.editEmail("guest-journey@example.com")
        signup.editPassword("NewPassword123!")
        signup.editConfirmation("NewPassword123!")
        #expect(await signup.submit(language: language, requiresGuestClaim: true) == .accepted)
        let result = try #require(accepted)
        #expect(result.tripId == token && AuthNavigation.route(for: result.account) == .verify)
        #expect(signup.password.isEmpty && signup.confirmation.isEmpty)
        #expect(try await store.recover() == nil)
        #expect(await secrets.get(for: token) == nil)
        let continuation = GuestContinuationRepository(database: database)
        for gate in [Gate.verify, .terms, .walkthrough] {
            #expect(try await continuation.consume(gate: gate) == nil)
        }
        let mail = try await source.inbox()
        guard case .verification(_, _, _, let link) = try #require(mail.last) else {
            Issue.record("Expected the registration verification email")
            return
        }
        _ = try await source.verifyEmail(link)
        #expect(try await source.fetchIdentity().hasVerifiedEmail)
        #expect(try await continuation.consume(gate: .app) == .trip(token))
        #expect(try await TripRepository(database: database).trips().isEmpty)
        #expect(try await continuation.consume(gate: .app) == nil)
        #expect(try await source.fetchTripDetail(id: token).trip.id == token)
        try await database.close()
    }

    private func waitFor(
        sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition(), sourceLocation: sourceLocation)
    }

    private func finishChecking(_ model: MemberWizardModel, clock: CheckingTestClock, start: Double) async throws {
        try await waitFor { clock.deadlines.contains(start + 1.2) || model.checking.failure != nil }
        try #require(model.checking.failure == nil, "Review failed: \(String(describing: model.checking.failure))")
        clock.advance(to: start + 1.2)
        try await waitFor { clock.deadlines.contains(start + 1.5) }
        clock.advance(to: start + 1.5)
        try await waitFor { model.draft.state.step != .checking || model.checking.failure != nil }
        #expect(model.checking.failure == nil)
    }
}

private actor GuestJourneyDevice: DeviceIdentityPersistence {
    private var value: String?
    func readDeviceID() -> String? { value }
    func writeDeviceID(_ value: String) { self.value = value }
}

import AppCore
import DataAccess
import Foundation
import LocalStore
import Reminders
import Testing
import TripWizard

@Suite struct WizardSaveRecoveryTests {
    @Test(arguments: [true, false]) @MainActor
    func onlySuccessfulFirstTripSaveQueuesReminders(firstTrip: Bool) async throws {
        let fixture = try await completionFixture(firstTrip: firstTrip)
        try await SettingsRepository(database: fixture.database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        let offer = FirstTripRemindersOffer(database: fixture.database)
        #expect(try await offer.consume(permission: .undetermined) == false)
        await fixture.source.configure(saveFailure: .offline)
        fixture.model.savePlan()
        try await eventually { fixture.model.draft.state.saveFailure?.kind == .offline }
        #expect(try await offer.consume(permission: .undetermined) == false)
        await fixture.source.configure()
        fixture.model.savePlan()
        try await eventually { fixture.model.createdTripID == "created" }
        #expect(try await offer.consume(permission: .undetermined) == firstTrip)
        #expect(try await offer.consume(permission: .undetermined) == false)
        try await fixture.database.close()
    }

    @Test @MainActor func savedTripIDIsDurableBeforePullAndRecoverySkipsCreate() async throws {
        let gate = GenerationGate()
        let fixture = try await completionFixture(
            effects: TripGenerationEffects(
                mergeProfile: { _ in }, pullCreatedTrip: { _ in await gate.wait() }, requestSync: {}))
        fixture.model.savePlan()
        var recovered: MemberWizardDraft?
        try await eventually {
            recovered = try? await fixture.store.recover()
            return recovered?.state.savedTripId != nil
        }
        let saved = try #require(recovered)
        try await SettingsRepository(database: fixture.database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        let offer = FirstTripRemindersOffer(database: fixture.database)
        #expect(try await offer.consume(permission: .undetermined) == false)
        #expect(saved.state.step == .calculating && saved.state.savedTripId == "created")
        #expect(await fixture.source.count("save") == 1 && fixture.model.createdTripID == nil)
        let nextService = TripGenerationService(
            source: fixture.source,
            effects: TripGenerationEffects(
                mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {}))
        let nextModel = MemberWizardModel(
            draft: saved, store: fixture.store, search: noAirportSearch(), generation: nextService)
        nextModel.resumeCompletion()
        try await eventually { nextModel.createdTripID == "created" }
        #expect(await fixture.source.count("save") == 1)
        #expect(try await fixture.store.recover() == nil)
        #expect(try await offer.consume(permission: .undetermined) == true)
        await gate.open()
        try await eventually { fixture.model.createdTripID == "created" }
        #expect(try await offer.consume(permission: .undetermined) == false)
        try await fixture.database.close()
    }

    @Test @MainActor func recoveryRetainsStepOpenSheetFailuresAndCheckedInput() async throws {
        let fixture = try await completionFixture(optional: true)
        var draft = fixture.model.draft
        draft.state.step = .fineTune
        draft.state.promptSheetID = draft.state.review?.prompts.first?.id
        draft.state.saveFailure = WizardSaveFailure(kind: .throttle, retryAt: fixture.clock.now.addingTimeInterval(42))
        draft.state.revisit = draft.state.checkedInput
        draft.state.revision += 1
        try await fixture.store.persist(draft)
        #expect(try await fixture.store.recover() == draft)
        let data = try JSONEncoder().encode(draft.state)
        #expect(try JSONDecoder().decode(MemberWizardState.self, from: data) == draft.state)
        try await fixture.close()
    }

    @Test @MainActor func oldContinuationDraftDecodesAndBecomesReadyOrFineTune() async throws {
        let fixture = try await completionFixture()
        var draft = fixture.model.draft
        draft.state.step = .continuation
        var json = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(draft.state))
        for field in [
            "checkedInput", "reviewedAt", "promptSheetID", "saveFailure", "returnToReady", "revisit", "updated",
        ] { json[field] = nil }
        draft.state = try JSONDecoder().decode(MemberWizardState.self, from: JSONEncoder().encode(json))
        draft.state.revision += 1
        try await fixture.store.persist(draft)
        let old = try #require(try await fixture.store.recover())
        #expect(old.state.step == .ready && old.state.checkedInput == nil)
        let restored = MemberWizardModel(draft: old, store: fixture.store, search: noAirportSearch())
        #expect(restored.needsReadyReview)
        draft.state.review?.prompts = MockWizardPrompts.make(
            input: fixture.model.reviewInput.input, profile: JSONObject())
        draft.state.revision += 1
        try await fixture.store.persist(draft)
        #expect(try await fixture.store.recover()?.state.step == .fineTune)
        try await fixture.close()
    }

    @Test func lostResponseAndManualRetryCreateOneMockTripAndSpendOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let seed = try MockAppSeed.make(now: now)
        let account = try #require(seed.accounts.values.first { $0.twoFactorCode == nil })
        let mock = MockDataSource(seed: seed, now: { now }, sleep: { _ in })
        _ = try await mock.signIn(
            PasswordSignInInput(
                email: account.snapshot.email, password: account.password, deviceID: UUID().uuidString,
                deviceName: "Tests"))
        let source = try GenerationSource(mock: mock)
        let service = TripGenerationService(
            source: source,
            effects: TripGenerationEffects(mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {}))
        let review = try await service.review(instance: "lost", input: ApiTripReviewInput(input: generationInput()))
        let initial = TripGenerationState(instance: "lost", input: review.input, review: review.review)
        let before = try await mock.fetchTrips().count
        await source.loseSaveResponseOnce()
        let lost = try await service.save(initial)
        #expect(lost.outcome == .failed(.offline) && lost.state.savedTripId == nil)
        #expect(try await mock.fetchTrips().count == before + 1)
        let recoveredService = TripGenerationService(
            source: source,
            effects: TripGenerationEffects(mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {}))
        let retry = try await recoveredService.save(lost.state)
        #expect(retry.state.savedTripId == review.review.identity.token)
        #expect(try await mock.fetchTrips().count == before + 1)
        #expect(await source.count("save") == 2)
        let balance = try await mock.fetchAccount().settings.planCredits["credits"]
        #expect(balance == .number(Decimal(review.review.price.balance - review.review.price.cost)))
    }
}

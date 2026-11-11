import AppCore
import DataAccess
import Foundation
import LocalStore
import Reminders
import Testing
import TripWizard

@Suite struct WizardSaveRecoveryTests {
    @Test @MainActor func recoveryDeleteFailureStillCompletesTheSavedTrip() async throws {
        let fixture = try await completionFixture(firstTrip: false)
        try await fixture.database.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_recovery_delete BEFORE DELETE ON drafts
                    BEGIN SELECT RAISE(FAIL, 'injected delete failure'); END
                    """)
        }
        fixture.model.savePlan()
        try await eventually { fixture.model.createdTripID == "created" }
        #expect(fixture.model.closed && fixture.model.draft.state.saveFailure == nil)
        #expect(await fixture.source.count("save") == 1)
        let recovery = try #require(try await fixture.store.recover())
        #expect(recovery.state.savedTripId == "created" && recovery.state.step == .calculating)
        try await fixture.database.write { try $0.execute(sql: "DROP TRIGGER fail_recovery_delete") }
        let restarted = MemberWizardModel(
            draft: recovery, store: fixture.store, search: noAirportSearch(),
            generation: TripGenerationService(
                source: fixture.source,
                effects: TripGenerationEffects(
                    mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {})))
        restarted.resumeCompletion()
        try await eventually { restarted.createdTripID == "created" }
        #expect(await fixture.source.count("save") == 1)
        #expect(try await fixture.store.recover() == nil)
        try await fixture.database.close()
    }

    @Test @MainActor func transientSavedIDWriteFailurePersistsKnownTripBeforeRecovery() async throws {
        let fixture = try await completionFixture()
        let recovery = fixture.model.draft
        let generation = FailingSavedIDWriteGeneration(service: fixture.service)
        let model = MemberWizardModel(
            draft: recovery, store: fixture.store, search: noAirportSearch(), now: { fixture.clock.now },
            generation: generation)
        model.savePlan()
        try await eventually { model.draft.state.saveFailure != nil }
        await model.flush()
        let saved = try #require(try await fixture.store.recover())
        #expect(saved.state.savedTripId == "created" && saved.state.step == .ready)
        #expect(!model.needsReadyReview)
        let restarted = MemberWizardModel(
            draft: saved, store: fixture.store, search: noAirportSearch(), now: { fixture.clock.now },
            generation: TripGenerationService(
                source: fixture.source,
                effects: TripGenerationEffects(
                    mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {})))
        restarted.resumeCompletion()
        #expect(!restarted.needsReadyReview && !restarted.reviewing)
        restarted.savePlan()
        try await eventually { restarted.createdTripID == "created" }
        #expect(await fixture.source.count("save") == 1)
        #expect(await fixture.source.count("review") == 0)
        try await fixture.database.close()
    }

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
        #expect(balance == .number(Decimal((review.review.price?.balance ?? 0) - (review.review.price?.cost ?? 0))))
    }
}

private struct FailingSavedIDWriteGeneration: MemberWizardGeneration {
    let service: TripGenerationService
    func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult {
        try await service.review(instance: instance, input: input)
    }
    func save(
        _ state: TripGenerationState, didCreate: @escaping @Sendable (String) async throws -> Void
    ) async throws -> TripGenerationSaveResult {
        try await service.save(state) { _ in throw StoreFailure.unavailable }
    }
    func cancelReviews(instance: String) async { await service.cancelReviews(instance: instance) }
    func cancel() async { await service.cancel() }
}

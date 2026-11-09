import AppCore
import DataAccess
import Foundation
import LocalStore
import Testing
import TripWizard

@Suite struct WizardCompletionTests {
    @Test @MainActor func readyExpiresAtThirtyMinutesAndChangedInputsInvalidateIt() async throws {
        let fixture = try await completionFixture()
        let model = fixture.model
        #expect(!model.needsReadyReview)
        fixture.clock.advance(1799.999)
        #expect(!model.needsReadyReview)
        fixture.clock.advance(0.001)
        #expect(model.needsReadyReview)
        model.readyTick()
        try await eventually { !model.reviewing && !model.needsReadyReview }
        #expect(await fixture.source.count("review") == 1)
        model.editForm { $0.preparation.days = 1 }
        #expect(model.needsReadyReview)
        model.savePlan()
        try await eventually { !model.reviewing && !model.needsReadyReview }
        #expect(await fixture.source.count("save") == 0)
        #expect(await fixture.source.count("review") == 2)
        #expect(model.draft.state.step == .ready)
        try await fixture.close()
    }

    @Test @MainActor func unchangedRevisitReturnsToReadyWithoutChecking() async throws {
        let fixture = try await completionFixture()
        fixture.model.revisit(.outbound)
        #expect(fixture.model.draft.state.returnToReady == true)
        fixture.model.finishFlightInput()
        #expect(fixture.model.draft.state.step == .ready)
        #expect(await fixture.source.count("review") == 0)
        fixture.model.revisit(.fineTune)
        fixture.model.finishFineTune()
        #expect(fixture.model.draft.state.step == .ready)
        #expect(await fixture.source.count("review") == 0)
        try await fixture.close()
    }

    @Test @MainActor func optionalAnswerIsScopedAndContinueReReviews() async throws {
        let fixture = try await completionFixture(optional: true)
        let model = fixture.model
        model.revisit(.fineTune)
        let seat = try #require(model.optionalPrompts.first { $0.kind == .seatSide })
        model.openPrompt(seat.id)
        try model.answerOptional(seat, values: ["seat_window": .string("right")])
        #expect(model.draft.form.legs[0].seatWindow == "right")
        #expect(model.draft.state.promptSheetID == nil && model.needsReadyReview)
        model.finishFineTune()
        try await eventually { model.draft.state.step == .ready && !model.reviewing }
        #expect(await fixture.source.count("review") == 1)
        #expect(await fixture.source.reviewInputs.last?.input.outbound.legs.first?.seatWindow == "right")
        let caffeine = try #require(fixture.review.prompts.first { $0.kind == .cups })
        var input = model.reviewInput
        input = try TripGenerationService.applyingAnswers(
            input: input, review: fixture.review,
            answers: [caffeine.id: ["caffeine_habit": .string("cups"), "cups_tea": .number(2)]])
        #expect(input.profile?["cups_tea"] == .number(2))
        try await fixture.close()
    }

    @Test @MainActor func fineTuneWithoutChangesOpensReadyAndErrorsWaitForManualRetry() async throws {
        let fixture = try await completionFixture(optional: true)
        let model = fixture.model
        model.revisit(.fineTune)
        model.finishFineTune()
        #expect(model.draft.state.step == .ready)
        model.revisit(.fineTune)
        model.editForm { $0.preparation.days = 0 }
        await fixture.source.configure(reviewFailure: .offline)
        model.finishFineTune()
        try await eventually { model.checking.failure == .offline }
        model.resumeChecking()
        #expect(await fixture.source.count("review") == 1)
        #expect(model.draft.state.step == .checking)
        try await fixture.close()
    }

    @Test @MainActor func saveFailureDoesNotRetryAndManualRetryKeepsIdentity() async throws {
        let fixture = try await completionFixture()
        let model = fixture.model
        let identity = model.draft.form.identity
        await fixture.source.configure(saveFailure: .offline)
        model.savePlan()
        try await eventually { model.draft.state.saveFailure?.kind == .offline }
        for _ in 0..<10 { model.readyTick() }
        #expect(model.draft.state.step == .ready && model.draft.form.identity == identity)
        #expect(await fixture.source.count("save") == 1)
        #expect(await fixture.source.count("review") == 0)
        await fixture.source.configure()
        model.savePlan()
        try await eventually { model.createdTripID == "created" }
        #expect(await fixture.source.count("save") == 2)
        #expect(try await fixture.store.recover() == nil)
        try await fixture.database.close()
    }

    @Test @MainActor func failedSaveStillAllowsTheThirtyMinuteReviewRefresh() async throws {
        let fixture = try await completionFixture()
        await fixture.source.configure(saveFailure: .offline)
        fixture.model.savePlan()
        try await eventually { fixture.model.draft.state.saveFailure != nil }
        fixture.clock.advance(1800)
        fixture.model.readyTick()
        try await eventually { !fixture.model.reviewing && fixture.model.draft.state.saveFailure == nil }
        #expect(await fixture.source.count("review") == 1)
        #expect(await fixture.source.count("save") == 1)
        try await fixture.close()
    }

    @Test @MainActor func throttleCountdownUsesCeilingAndGuardsManualRetry() async throws {
        let fixture = try await completionFixture()
        let model = fixture.model
        await fixture.source.configure(saveFailure: .throttled(retryAfterSeconds: 42, status: 429))
        model.savePlan()
        try await eventually { model.retrySeconds == 42 }
        model.savePlan()
        fixture.clock.advance(41.01)
        model.readyTick()
        #expect(model.retrySeconds == 1 && !model.canSave)
        #expect(await fixture.source.count("save") == 1)
        fixture.clock.advance(0.99)
        model.readyTick()
        #expect(model.retrySeconds == 0 && model.canSave)
        #expect(await fixture.source.count("save") == 1)
        await fixture.source.configure()
        model.savePlan()
        try await eventually { model.createdTripID == "created" }
        try await fixture.database.close()
    }

    @Test(arguments: [DataFailure.reviewExpired, .notEnoughCredits]) @MainActor
    func expiredOrCreditFailureClearsIdentityBeforeReadyRecheck(_ failure: DataFailure) async throws {
        let fixture = try await completionFixture()
        let gate = GenerationGate()
        await fixture.source.configure(saveFailure: failure, beforeReview: { await gate.wait() })
        fixture.model.savePlan()
        try await eventually { fixture.model.reviewing }
        #expect(fixture.model.draft.state.step == .ready)
        #expect(fixture.model.draft.form.identity == nil)
        #expect(fixture.model.draft.state.savedTripId == nil)
        #expect(fixture.model.draft.state.saveFailure == nil)
        await gate.open()
        try await eventually { !fixture.model.reviewing }
        #expect(await fixture.source.count("review") == 1)
        #expect(await fixture.source.count("save") == 1)
        #expect(await fixture.source.reviewInputs.last?.identity == nil)
        try await fixture.close()
    }

    @Test @MainActor func returningToForegroundCanRefreshNoCreditsWithoutSaving() async throws {
        let fixture = try await completionFixture()
        var review = fixture.review
        review.canSave = false
        review.price.balance = 0
        review.saveBlockedReason = "Not enough credits"
        await fixture.source.queueReviews([.success(review)])
        fixture.model.readyTick(force: true)
        try await eventually { !fixture.model.reviewing }
        #expect(fixture.model.credits == .unavailable && !fixture.model.canSave)
        fixture.model.savePlan()
        #expect(await fixture.source.count("save") == 0)
        fixture.model.readyTick(force: true)
        try await eventually { !fixture.model.reviewing }
        #expect(fixture.model.credits == .credits && fixture.model.canSave)
        #expect(await fixture.source.count("review") == 2)
        #expect(await fixture.source.count("save") == 0)
        try await fixture.close()
    }

    @Test @MainActor func calculatingRejectsBackCloseAndDoubleSave() async throws {
        let fixture = try await completionFixture()
        let gate = GenerationGate()
        await fixture.source.configure(beforeSave: { await gate.wait() })
        fixture.model.savePlan()
        try await eventually { await fixture.source.count("save") == 1 }
        let path = fixture.model.navigationPath
        fixture.model.popNavigation(to: [], from: path)
        fixture.model.go(.whereTo)
        try await fixture.model.discard()
        fixture.model.savePlan()
        #expect(fixture.model.draft.state.step == .calculating && !fixture.model.closed)
        #expect(await fixture.source.count("save") == 1)
        await gate.open()
        try await eventually { fixture.model.createdTripID == "created" }
        try await fixture.database.close()
    }

    @Test func creditsCoverEveryReadyVariant() throws {
        var review = try generationReview()
        #expect(WizardCredits(review) == .credits)
        review.price.freeDirections = [.return]
        #expect(WizardCredits(review) == .oneFree)
        review.price.cost = 0
        #expect(WizardCredits(review) == .free)
        review.price.unlimited = true
        #expect(WizardCredits(review) == .unlimited)
        review.canSave = false
        review.saveBlockedReason = "Not enough credits"
        #expect(WizardCredits(review) == .unavailable)
    }

    @Test func sheetValidationAcceptsCommaRatingAndRejectsMissingDrinks() throws {
        let prompts = MockWizardPrompts.make(input: try generationInput(), profile: JSONObject())
        let cups = try #require(prompts.first { $0.kind == .cups })
        #expect(WizardOptionalAnswer.error(cups, values: ["caffeine_habit": .string("cups")]) != nil)
        #expect(WizardOptionalAnswer.error(cups, values: ["caffeine_habit": .string("non_user")]) == nil)
        #expect(WizardOptionalAnswer.error(cups, values: ["cups_tea": .number(1)]) == nil)
        let blue = try #require(prompts.first { $0.kind == .blueBlockers })
        for text in ["0", "12", "NaN", ""] {
            #expect(
                WizardOptionalAnswer.error(
                    blue, values: ["blue_blockers": .string("rated"), "blue_blocker_mdfd": .string(text)]) != nil)
        }
        #expect(
            WizardOptionalAnswer.error(
                blue, values: ["blue_blockers": .string("rated"), "blue_blocker_mdfd": .string("1,5")]) == nil)
    }
}

struct CompletionFixture {
    let model: MemberWizardModel
    let source: GenerationSource
    let service: TripGenerationService
    let store: MemberWizardStore
    let database: AccountDatabase
    let clock: WizardTestClock
    let review: ApiTripReview
    @MainActor func close() async throws {
        try await model.discard()
        try await database.close()
    }
}

@MainActor func completionFixture(
    optional: Bool = false, effects: TripGenerationEffects? = nil, firstTrip: Bool = true
) async throws
    -> CompletionFixture
{
    let database = try await wizardDatabase()
    let clock = WizardTestClock()
    let store = MemberWizardStore(database: database, now: { clock.now })
    var draft = try await store.start()
    draft.state.firstTrip = firstTrip
    draft.form = try WizardForm(input: generationInput())
    // Keep the fixture's flight future while testing a freely advancing Ready clock.
    for index in draft.form.legs.indices {
        draft.form.legs[index].departLocal = "2028-10-12T14:40"
        draft.form.legs[index].arriveLocal = "2028-10-13T09:15"
    }
    var review = try generationReview()
    if optional {
        review.prompts = MockWizardPrompts.make(
            input: draft.form.reviewInput(identity: nil).input, profile: JSONObject())
    }
    draft.form.identity = review.identity
    draft.state.review = review
    draft.state.sleepNeeded = false
    draft.state.step = .ready
    draft.state.reviewedAt = clock.now
    let source = try GenerationSource()
    let service = TripGenerationService(
        source: source,
        effects: effects ?? TripGenerationEffects(mergeProfile: { _ in }, pullCreatedTrip: { _ in }, requestSync: {}))
    let model = MemberWizardModel(
        draft: draft, store: store, search: noAirportSearch(), now: { clock.now }, generation: service)
    var checked = model.draft
    checked.state.checkedInput = model.inputFingerprint
    try await store.persist(checked)
    let active = MemberWizardModel(
        draft: checked, store: store, search: noAirportSearch(), now: { clock.now }, generation: service)
    return CompletionFixture(
        model: active, source: source, service: service, store: store, database: database, clock: clock, review: review)
}

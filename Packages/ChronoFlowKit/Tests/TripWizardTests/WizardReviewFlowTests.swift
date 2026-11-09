import AppCore
import DataAccess
import Foundation
import LocalStore
import Sync
import Testing
import TripWizard

@Suite struct WizardReviewFlowTests {
    @Test @MainActor func sleepIsRequiredUntilAnsweredAndNotSureCounts() async throws {
        let fixture = try await reviewFixture(sleepNeeded: true)
        let model = fixture.model
        defer { model.cancelCheck() }
        model.finishFlightInput()
        #expect(model.draft.state.step == .sleep)
        model.beginChecking()
        #expect(model.draft.state.step == .sleep)
        #expect(await fixture.source.count("review") == 0)
        model.setSleep("habitual_bed", value: .string("23:30"))
        model.setSleep("habitual_wake", value: .string("07:15"))
        #expect(!model.sleepComplete)
        model.setSleep("chronotype", value: .null)
        #expect(model.sleepComplete)
        #expect(model.finishSleep())
        try await finishCheck(fixture)
        #expect(model.draft.state.step == .continuation && !model.draft.state.sleepNeeded)
        #expect(model.lastInputStep == .sleep)
        #expect(await fixture.source.reviewInputs.last?.profile?["chronotype"] == .null)
        #expect(
            try await SettingsRepository(database: fixture.database).settings().first { $0.section == "sleepAnswered" }?
                .value.decode(Bool.self) == true)
        let saved = try await SettingsRepository(database: fixture.database).settings().first {
            $0.section == "bodyClock"
        }?.value.decode(JSONObject.self)
        #expect(saved?["habitualBed"] == .string("23:30") && saved?["habitualWake"] == .string("07:15"))
        try await model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func invalidSleepDurationStaysAtSleep() async throws {
        let fixture = try await reviewFixture(sleepNeeded: true)
        let model = fixture.model
        model.go(.sleep)
        model.setSleep("habitual_bed", value: .string("23:30"))
        model.setSleep("habitual_wake", value: .string("00:30"))
        model.setSleep("chronotype", value: .string("early"))
        #expect(!model.finishSleep())
        #expect(model.draft.fieldErrors["profile.habitual_bed"]?.key == "Check your bedtime and wake-up time.")
        #expect(await fixture.source.count("review") == 0)
        try await model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func failedRequestShowsOfflineAndManualRetryChecksAgain() async throws {
        let fixture = try await reviewFixture()
        await fixture.source.configure(reviewFailure: .offline)
        fixture.model.beginChecking()
        try await eventually { fixture.model.checking.failure == .offline }
        #expect(fixture.model.draft.state.step == .checking)
        #expect(await fixture.source.count("review") == 1)
        await fixture.source.configure()
        fixture.model.beginChecking()
        try await finishCheck(fixture, count: 2)
        #expect(fixture.model.draft.state.step == .continuation)
        try await fixture.model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func throttleUsesServerDeadlineAndBlocksRetry() async throws {
        let fixture = try await reviewFixture()
        await fixture.source.configure(reviewFailure: .throttled(retryAfterSeconds: 2.4, status: 429))
        fixture.model.beginChecking()
        try await eventually { fixture.model.retrySeconds == 3 }
        fixture.model.beginChecking()
        #expect(await fixture.source.count("review") == 1)
        fixture.clock.advance(to: 1)
        try await eventually { fixture.model.retrySeconds == 2 }
        fixture.clock.advance(to: 2)
        try await eventually { fixture.model.retrySeconds == 1 }
        fixture.clock.advance(to: 2.4)
        try await eventually { fixture.model.retrySeconds == 0 }
        #expect(await fixture.source.count("review") == 1)
        try await fixture.model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func questionAnswersReReviewWithIdentityAndReachSeam() async throws {
        let fixture = try await reviewFixture()
        var first = try generationReview()
        first.prompts = [screeningPrompt("shift_work")]
        let final = try generationReview()
        await fixture.source.queueReviews([.success(first), .success(final)])
        fixture.model.beginChecking()
        try await finishCheck(fixture)
        #expect(fixture.model.currentQuestion?.fields == ["shift_work"])
        #expect(fixture.model.draft.state.step == .question)
        let progress = fixture.model.progress
        fixture.model.answerQuestion(.bool(false))
        fixture.model.answerQuestion(.bool(true))
        try await eventually { fixture.clock.deadlines.contains(1.75) }
        #expect(fixture.model.choicePending && fixture.model.draft.state.profile["shift_work"] == .bool(false))
        fixture.clock.advance(to: 1.75)
        try await eventually { fixture.model.draft.state.step == .checking }
        #expect(fixture.model.progress >= progress)
        try await finishCheck(fixture, count: 2, start: 1.75)
        #expect(fixture.model.draft.state.step == .continuation)
        let input = try #require(await fixture.source.reviewInputs.last)
        #expect(input.profile?["shift_work"] == .bool(false) && input.identity == first.identity)
        try await fixture.model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func screeningExclusionCanClearAnswersAndReviewAgain() async throws {
        let fixture = try await reviewFixture()
        var first = try generationReview()
        first.prompts = [screeningPrompt("shift_work")]
        var excluded = first
        excluded.status = .noPlan
        excluded.prompts = []
        excluded.reasons = [CopyLine(key: "Plans are only available for people aged 18 and over.", args: [])]
        await fixture.source.queueReviews([.success(first), .success(excluded), .success(first)])
        fixture.model.beginChecking()
        try await finishCheck(fixture)
        fixture.model.answerQuestion(.bool(true))
        try await eventually { fixture.clock.deadlines.contains(1.75) }
        fixture.clock.advance(to: 1.75)
        try await finishCheck(fixture, count: 2, start: 1.75)
        #expect(fixture.model.draft.state.step == .excluded)
        fixture.model.changeExcludedAnswers()
        try await finishCheck(fixture, count: 3, start: 3.25)
        #expect(fixture.model.draft.state.step == .question)
        #expect(await fixture.source.reviewInputs.last?.profile?["shift_work"] == .null)
        try await fixture.model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func returnChoiceRetainsWebEndOrReplacesItAndGuardsDoubleTap() async throws {
        let fixture = try await reviewFixture()
        var draft = fixture.model.draft
        draft.form.end.kind = "nights"
        draft.form.end.nights = 9
        let model = MemberWizardModel(
            draft: draft, store: fixture.store, search: noAirportSearch(), checkingClock: fixture.clock.clock)
        model.chooseReturn("return_legs")
        model.chooseReturn("one_way")
        #expect(model.draft.form.end.kind == "return_legs" && model.draft.form.end.nights == nil)
        #expect(model.draft.form.legs.last?.departLocal == "" && model.draft.form.legs.last?.arriveLocal == "")
        #expect(
            model.draft.form.legs.last?.fromIata == model.draft.form.legs[model.draft.form.returnBoundary - 1].toIata)
        #expect(model.draft.form.legs.last?.toIata == model.draft.form.legs[0].fromIata)
        try await eventually { fixture.clock.deadlines.contains(0.25) }
        fixture.clock.advance(to: 0.25)
        try await eventually { model.draft.state.step == .returnFlight }
        try await model.discard()
        try await fixture.database.close()
    }

    @Test @MainActor func backCancelsCheckingAndRecoveryKeepsQuestionsAndLastInput() async throws {
        let fixture = try await reviewFixture()
        await fixture.source.configure(beforeReview: { try await fixture.clock.clock.sleepUntil(100) })
        fixture.model.beginChecking()
        try await eventually { await fixture.source.count("review") == 1 }
        fixture.model.go(.returnChoice)
        await fixture.source.configure()
        var review = try generationReview()
        review.prompts = [screeningPrompt("shift_work"), screeningPrompt("bipolar")]
        await fixture.source.queueReviews([.success(review)])
        fixture.model.beginChecking()
        try await finishCheck(fixture, count: 2)
        let model = fixture.model
        #expect(model.lastInputStep == .returnChoice)
        model.answerQuestion(.bool(false))
        try await eventually { fixture.clock.deadlines.contains(1.75) }
        fixture.clock.advance(to: 1.75)
        try await eventually { model.draft.state.questionIndex == 1 }
        model.backFromQuestion()
        #expect(model.draft.state.step == .question && model.draft.state.questionIndex == 0)
        await model.flush()
        let recovered = try #require(try await fixture.store.recover())
        #expect(recovered.state.review == review && recovered.state.questions == review.prompts)
        #expect(recovered.state.profile["shift_work"] == .bool(false))
        model.backFromQuestion()
        #expect(model.draft.state.step == .returnChoice)
        try await model.discard()
        try await fixture.database.close()
    }

    @Test func returnPastUsesFinalArrivalAndAirportZones() throws {
        var form = WizardForm()
        form.legs[0].fromIata = "AMS"
        form.legs[0].toIata = "HND"
        form.legs[0].departLocal = "2026-10-10T14:00"
        form.legs[0].arriveLocal = "2026-10-11T09:00"
        form.addReturn()
        form.legs[1].toIata = "AMS"
        form.legs[1].departLocal = "2026-11-12T10:00"
        form.legs[1].arriveLocal = "2026-11-12T18:00"
        let airports = [
            "AMS": wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            "HND": wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"),
        ]
        let now = WizardDateTime.date("2026-11-09T12:00")!
        #expect(WizardFlightRules.errors(form: form, airports: airports, now: now, checkPast: true).isEmpty)
        form.legs[1].departLocal = "2026-10-12T10:00"
        form.legs[1].arriveLocal = "2026-10-12T18:00"
        #expect(WizardFlightRules.errors(form: form, airports: airports, now: now, checkPast: false).isEmpty)
        #expect(WizardFlightRules.errors(form: form, airports: airports, now: now, checkPast: true)["review"] != nil)
        form.legs[1].arriveLocal = "2026-10-11T18:00"
        #expect(
            WizardFlightRules.errors(form: form, airports: airports, now: now, checkPast: true)["legs.1.arriveLocal"]
                != nil)
    }
}

private struct ReviewFixture {
    let model: MemberWizardModel
    let source: GenerationSource
    let clock: CheckingTestClock
    let database: AccountDatabase
    let store: MemberWizardStore
}

@MainActor private func reviewFixture(sleepNeeded: Bool = false) async throws -> ReviewFixture {
    let database = try await wizardDatabase()
    let store = MemberWizardStore(database: database)
    var draft = try await store.start()
    draft.form = try WizardForm(input: generationInput())
    draft.state.step = .returnChoice
    draft.state.sleepNeeded = sleepNeeded
    let source = try GenerationSource()
    let clock = CheckingTestClock()
    let epoch = SyncEpoch(accountID: try AccountID("019a562b-8000-7000-8000-000000000001"), generation: 1)
    let effects = TripGenerationEffects.storing(database: database, source: source, epoch: epoch, requestSync: {})
    let generation = TripGenerationService(source: source, effects: effects)
    let model = MemberWizardModel(
        draft: draft, store: store, search: noAirportSearch(), now: { .distantPast }, generation: generation,
        checkingClock: clock.clock)
    return ReviewFixture(model: model, source: source, clock: clock, database: database, store: store)
}

@MainActor private func finishCheck(_ fixture: ReviewFixture, count: Int = 1, start: Double = 0) async throws {
    try await eventually { await fixture.source.count("review") == count && fixture.clock.waiterCount >= 2 }
    fixture.clock.advance(to: start + 1.2)
    try await eventually { fixture.model.checking.ticks == 3 && fixture.clock.deadlines.contains(start + 1.5) }
    fixture.clock.advance(to: start + 1.5)
    try await eventually { fixture.model.draft.state.step != .checking || fixture.model.checking.failure != nil }
}

private func screeningPrompt(_ field: String) -> ApiReviewPrompt {
    ApiReviewPrompt(
        id: "screening:\(field)", kind: .screening, blocking: true, required: true,
        text: CopyLine(key: "Do you have bipolar disorder?", args: []), scope: ApiReviewPromptScope(), target: .profile,
        fields: [field], answer: [:], shape: ApiReviewPromptShape(kind: .boolean, options: []))
}

import AppCore
import DataAccess
import Foundation
import Testing

@testable import TripWizard

@Suite @MainActor struct GuestWizardModeTests {
    @Test func guestFineTuneUsesOnlyTheDrawnRowsAndLeavesMemberRowsAvailable() async throws {
        let fixture = try await guestModeFixture(ready: true)
        let model = fixture.model
        var input = model.reviewInput.input
        input.return = input.outbound
        model.draft.state.review?.prompts = MockWizardPrompts.make(input: input, profile: JSONObject())
        #expect(
            Set(model.optionalPrompts.map(\.kind)) == [
                .room, .latestWake, .seatSide, .cups, .lightDevice, .blueBlockers,
            ])
        model.draft.state.mode = .member
        #expect(model.optionalPrompts.contains { $0.kind == .lateCheckOut })
        #expect(model.optionalPrompts.contains { $0.kind == .preDepartureBusyHours })
        #expect(model.optionalPrompts.contains { $0.kind == .freeDayTimes })
        try await fixture.close()
    }

    @Test func questionsRowReopensSupportedAnswersAndReturnsToReady() async throws {
        let fixture = try await guestModeFixture(ready: true)
        let model = fixture.model
        model.draft.state.profile["age_band"] = .string("18_64")
        model.draft.state.profile["shift_work"] = .bool(false)
        #expect(model.guestAnsweredQuestionCount == 2)
        model.revisitGuestQuestions()
        #expect(model.draft.state.step == .question && model.draft.state.questionIndex == 0)
        #expect(model.draft.state.questions?.map(\.fields) == [["age_band"], ["shift_work"]])
        #expect(model.draft.state.profile["age_band"] == .string("18_64"))
        #expect(model.draft.state.profile["shift_work"] == .bool(false))
        #expect(model.draft.state.returnToReady == true)
        try await fixture.close()
    }

    @Test func readyWaitsForTheSignupSheetAndDismissalAllowsAnotherRequest() async throws {
        let fixture = try await guestModeFixture(ready: true)
        let model = fixture.model
        model.savePlan()
        #expect(model.saveOutcome == .signUpRequested)
        model.setGuestAuthenticationPresented(true)
        #expect(model.saveOutcome == nil)
        model.draft.state.reviewedAt = nil
        model.readyTick(force: true)
        model.savePlan()
        #expect(model.draft.state.step == .ready && model.saveOutcome == nil)
        model.setGuestAuthenticationPresented(false)
        model.readyTick()
        #expect(model.draft.state.step == .checking)
        try await fixture.close()
    }

    @Test func legacyStateDecodesAsMemberAndModeRoundTrips() throws {
        let encoder = JSONEncoder()
        var state = MemberWizardState()
        var json = try JSONSerialization.jsonObject(with: encoder.encode(state)) as! [String: Any]
        json.removeValue(forKey: "mode")
        #expect(
            try JSONDecoder().decode(MemberWizardState.self, from: JSONSerialization.data(withJSONObject: json)).mode
                == .member)
        state.mode = .guest
        #expect(try JSONDecoder().decode(MemberWizardState.self, from: encoder.encode(state)) == state)
    }

    @Test func guestPathBackTargetsAndSleepAreMandatory() async throws {
        let fixture = try await guestModeFixture()
        let model = fixture.model
        model.go(.outbound)
        model.finishOutboundStep()
        #expect(model.draft.state.step == .sleep && model.lastInputStep == .sleep)
        #expect(model.navigationPath == [.outbound, .sleep])
        model.go(.checking)
        var path = model.navigationPath
        model.popNavigation(to: Array(path.dropLast()), from: path)
        #expect(model.draft.state.step == .sleep)
        model.draft.state.questions = [guestAgePrompt()]
        model.go(.question)
        #expect(model.navigationPath == [.outbound, .sleep, .question(0)])
        path = model.navigationPath
        model.popNavigation(to: Array(path.dropLast()), from: path)
        #expect(model.draft.state.step == .sleep)
        model.go(.question)
        model.backFromQuestion()
        #expect(model.draft.state.step == .sleep)
        model.draft.state.sleepCompleted = false
        model.beginChecking()
        #expect(model.draft.state.step == .sleep)
        model.editForm {
            $0.addReturn()
            $0.override.enabled = true
        }
        #expect(model.draft.form.end.kind == "one_way" && model.draft.form.legs.count == 1)
        #expect(!model.draft.form.override.enabled && model.draft.state.sleepNeeded)
        #expect(!model.showsReturnRow && !model.allowsSleepOverride)
        try await fixture.close()
    }

    @Test func guestWeightsAndForwardProgressFloor() async throws {
        let fixture = try await guestModeFixture()
        let model = fixture.model
        model.draft.form.legs[0].toIata = ""
        #expect(model.progress == 0.09)
        model.draft.form.legs[0].toIata = "HND"
        #expect(model.progress == 0.18)
        for (step, value) in [(MemberWizardStep.outbound, 0.30), (.sleep, 0.42), (.checking, 0.54), (.question, 0.54)] {
            model.go(step)
            #expect(model.progress == value)
        }
        model.draft.state.questionIndex = 1
        #expect(model.progress == 0.64)
        model.draft.state.checkingAnswers = true
        model.go(.checking)
        #expect(model.progress == 0.64)
        model.go(.fineTune)
        #expect(model.progress == 0.86)
        model.go(.ready)
        #expect(model.progress == 0.95)
        model.go(.checking)
        #expect(model.progress == 0.95)
        try await fixture.close()
    }

    @Test(arguments: ["identity", "emptyToken", "failure", "saveFailure", "fingerprint", "expired", "unchecked"])
    func readyRechecksEveryInvalidation(_ reason: String) async throws {
        let fixture = try await guestModeFixture(ready: true)
        let model = fixture.model
        #expect(!model.needsReadyReview)
        switch reason {
        case "identity": model.draft.form.identity = nil
        case "emptyToken": model.draft.form.identity?.token = ""
        case "failure": model.checking.failure = .offline
        case "saveFailure": model.draft.state.saveFailure = WizardSaveFailure(kind: .server)
        case "fingerprint": model.editForm { $0.preparation.days = 1 }
        case "expired": fixture.clock.advance(1800)
        default: model.draft.state.reviewedAt = nil
        }
        #expect(model.needsReadyReview)
        model.savePlan()
        #expect(model.draft.state.step == .checking && model.saveOutcome == nil)
        #expect(model.draft.state.returnToReady == true)
        try await fixture.close()
    }

    @Test func liveReadyRequestsSignUpWithoutSaving() async throws {
        let fixture = try await guestModeFixture(ready: true)
        let model = fixture.model
        fixture.clock.advance(1799.999)
        model.savePlan()
        #expect(model.saveOutcome == .signUpRequested && model.draft.state.step == .ready && !model.closed)
        #expect(model.createdTripID == nil && model.draft.state.savedTripId == nil)
        try await fixture.close()
    }

    @Test func exclusionResetKeepsSleepAndPreferences() async throws {
        let fixture = try await guestModeFixture()
        let model = fixture.model
        model.draft.state.profile["age_band"] = .string("under_18")
        model.draft.state.profile["shift_work"] = .bool(true)
        model.draft.state.profile["exclude_caffeine"] = .bool(true)
        model.go(.excluded)
        model.changeExcludedAnswers()
        #expect(model.draft.state.profile["age_band"] == .null && model.draft.state.profile["shift_work"] == .null)
        #expect(model.draft.state.profile["habitual_bed"] == .string("23:00"))
        #expect(model.draft.state.profile["exclude_caffeine"] == .bool(true))
        #expect(model.draft.state.step == .question && model.currentQuestion?.fields == ["age_band"])
        try await fixture.close()
    }

    @Test func guestPastArrivalCopyAndMemberNavigationStayDistinct() async throws {
        let fixture = try await guestModeFixture()
        let model = fixture.model
        let errors = WizardFlightRules.errors(
            form: model.draft.form, airports: [:], now: .distantFuture, checkPast: true, mode: .guest)
        #expect(errors.isEmpty)
        let airports = [
            "AMS": wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            "HND": wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"),
        ]
        #expect(
            WizardFlightRules.errors(
                form: model.draft.form, airports: airports, now: .distantFuture, checkPast: true, mode: .guest)[
                    "review"]?.key == "A new plan needs an upcoming arrival. Check your flight dates.")
        model.draft.state.mode = .member
        model.go(.outbound)
        model.finishOutboundStep()
        #expect(model.draft.state.step == .returnChoice)
        #expect(model.navigationPath == [.outbound, .returnChoice])
        #expect(model.showsReturnRow && model.allowsSleepOverride)
        try await fixture.close()
    }
}

private struct GuestModeFixture {
    let model: MemberWizardModel
    let clock: WizardTestClock
    let root: URL
    @MainActor func close() async throws {
        try await model.discard()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor private func guestModeFixture(ready: Bool = false) async throws -> GuestModeFixture {
    let root = guestStoreTestDirectory()
    let clock = WizardTestClock()
    let store = GuestWizardStore(applicationSupport: root, namespace: .mock, now: { clock.now })
    var draft = try await store.start()
    draft.form = try WizardForm(input: generationInput())
    draft.state.sleepCompleted = true
    if ready {
        draft.state.review = try generationReview()
        draft.form.identity = draft.state.review?.identity
        draft.state.reviewedAt = clock.now
        draft.state.step = .ready
    }
    let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch(), now: { clock.now })
    if ready { model.draft.state.checkedInput = model.inputFingerprint }
    return GuestModeFixture(model: model, clock: clock, root: root)
}

private func guestAgePrompt() -> ApiReviewPrompt {
    ApiReviewPrompt(
        id: "age", kind: .ageBand, blocking: true, required: true,
        text: CopyLine(key: "How old are you?", args: []), scope: ApiReviewPromptScope(), target: .profile,
        fields: ["age_band"], answer: [:],
        shape: ApiReviewPromptShape(kind: .options, options: ["under_18", "18_64", "65_plus"]))
}

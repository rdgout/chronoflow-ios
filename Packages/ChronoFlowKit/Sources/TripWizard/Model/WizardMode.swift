import AppCore
import Foundation

extension MemberWizardDraft {
    mutating func returnToReadyAfterExpiredClaim() {
        state.returnToReady = true
        state.checkingAnswers = nil
        state.reviewedAt = nil
        state.step = .ready
    }

    mutating func enforceGuestMode() {
        guard state.mode == .guest else { return }
        if form.end.kind == "return_legs" { form.removeReturn() }
        form.end = WizardEnd()
        form.override = WizardSleepOverride()
        state.sleepNeeded = true
        state.lastInputStep = .sleep
        state.savedProfile = nil
        state.firstTrip = false
    }
}

extension MemberWizardModel {
    public var guestAnsweredQuestionCount: Int {
        ["age_band", "shift_work"].filter {
            if let value = draft.state.profile[$0] { return value != .null }
            return false
        }.count
    }

    public func revisitGuestQuestions() {
        guard mode == .guest, draft.state.step == .ready, !reviewing, !closed else { return }
        draft.state.questions = guestScreeningQuestions
        draft.state.questionIndex = 0
        revisit(.question)
    }

    var guestScreeningQuestions: [ApiReviewPrompt] {
        [
            ApiReviewPrompt(
                id: "age_band", kind: .ageBand, blocking: true, required: true,
                text: CopyLine(key: "Which age group are you in?", args: []), scope: ApiReviewPromptScope(),
                target: .profile, fields: ["age_band"], answer: [:],
                shape: ApiReviewPromptShape(kind: .options, options: ["under_18", "18_64", "65_plus"])),
            ApiReviewPrompt(
                id: "shift_work", kind: .screening, blocking: true, required: true,
                text: CopyLine(
                    key:
                        "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?",
                    args: []),
                scope: ApiReviewPromptScope(), target: .profile, fields: ["shift_work"], answer: [:],
                shape: ApiReviewPromptShape(kind: .boolean, options: [])),
        ]
    }

    public var mode: WizardMode { draft.state.mode }
    public var showsReturnRow: Bool { mode == .member }
    public var allowsSleepOverride: Bool { mode == .member }

    public func guestReviewExpired() {
        guard mode == .guest, !closed else { return }
        draft.returnToReadyAfterExpiredClaim()
        saveOutcome = nil
        persist()
    }

    public func finishOutboundStep() {
        if mode == .guest { finishFlightInput() } else { go(.returnChoice) }
    }

    var guestStepProgress: Double {
        switch draft.state.step {
        case .whereTo: whereComplete ? 0.18 : 0.09
        case .outbound: 0.30
        case .sleep: 0.42
        case .checking, .excluded: draft.state.checkingAnswers == true ? 0.64 : 0.54
        case .question: (draft.state.questionIndex ?? 0) == 0 ? 0.54 : 0.64
        case .continuation, .fineTune: 0.86
        case .ready: 0.95
        case .calculating: 1
        case .returnChoice, .returnRoute, .returnFlight: 0.30
        }
    }

    func recheckGuestReady() {
        saveOutcome = nil
        draft.state.returnToReady = true
        beginChecking()
    }
}

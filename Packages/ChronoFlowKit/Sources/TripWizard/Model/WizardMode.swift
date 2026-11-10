import Foundation

extension MemberWizardDraft {
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
    public var mode: WizardMode { draft.state.mode }
    public var showsReturnRow: Bool { mode == .member }
    public var allowsSleepOverride: Bool { mode == .member }

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

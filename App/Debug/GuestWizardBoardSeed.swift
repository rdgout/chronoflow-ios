#if DEBUG
    import AppCore
    import Foundation
    import TripWizard

    enum GuestWizardBoardSeed {
        static func draft(_ original: MemberWizardDraft, board: String, locale: Locale) -> MemberWizardDraft {
            let shared =
                board == "WizardGuestJourney"
                ? "WizardSaveJourney"
                : [
                    "WizardWhereGuest": "WizardWhere", "WizardWhereGuestEmpty": "WizardWhereEmpty",
                    "WizardOutboundGuest": "WizardOutbound", "WizardOutboundPastGuest": "WizardOutboundPast",
                    "WizardCheckingGuest": "WizardChecking", "WizardDiscardGuest": "WizardOutbound",
                    "WizardReadyGuest": "WizardReady", "WizardReadyGuestFree": "WizardReadyFree",
                ][board] ?? (board.hasPrefix("GuestSignup") ? "WizardReady" : board)
            var draft = WizardBoardCaptureSeed.draft(original, board: shared, locale: locale)
            draft.state.mode = .guest
            draft.state.fromLastTrip = false
            draft.state.sleepNeeded = true
            draft.state.lastInputStep = .sleep
            draft.state.firstTrip = false
            if board == "WizardGuestJourney" {
                draft.state.step = .whereTo
                draft.state.profile["shift_work"] = .bool(false)
            }
            if [.fineTune, .ready].contains(draft.state.step) {
                draft.state.sleepCompleted = true
                draft.state.profile["age_band"] = .string("18_64")
                draft.state.profile["shift_work"] = .bool(false)
            }
            if board == "WizardOutboundPastGuest" {
                draft.fieldErrors["review"] = FieldMessage(
                    key: "A new plan needs an upcoming arrival. Check your flight dates.")
            }
            return draft
        }
    }
#endif

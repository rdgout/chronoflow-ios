#if DEBUG
    import AppCore
    import Foundation
    import TripWizard

    enum GuestWizardBoardSeed {
        static func draft(_ original: MemberWizardDraft, board: String, locale: Locale) -> MemberWizardDraft {
            let shared =
                [
                    "WizardWhereGuest": "WizardWhere", "WizardWhereGuestEmpty": "WizardWhereEmpty",
                    "WizardOutboundGuest": "WizardOutbound", "WizardOutboundPastGuest": "WizardOutboundPast",
                    "WizardCheckingGuest": "WizardChecking", "WizardDiscardGuest": "WizardOutbound",
                ][board] ?? board
            var draft = WizardBoardCaptureSeed.draft(original, board: shared, locale: locale)
            draft.state.mode = .guest
            draft.state.fromLastTrip = false
            draft.state.sleepNeeded = true
            draft.state.lastInputStep = .sleep
            draft.state.firstTrip = false
            if board == "WizardOutboundPastGuest" {
                draft.fieldErrors["review"] = FieldMessage(
                    key: "A new plan needs an upcoming arrival. Check your flight dates.")
            }
            return draft
        }
    }
#endif

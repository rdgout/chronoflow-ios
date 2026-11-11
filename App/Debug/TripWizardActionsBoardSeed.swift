#if DEBUG
    import AppCore
    import Foundation
    import TripWizard

    enum TripWizardActionsBoardSeed {
        static var boards: Set<String> {
            [
                "WizardEdit", "WizardEditChanged", "WizardEditNoReturn", "WizardEditReturn",
                "WizardEditReturnNoCredits", "WizardEditWeb", "WizardCheckingEdit", "WizardCheckOfflineEdit",
                "WizardCheckServerEdit", "WizardExcludedEdit", "WizardDiscardEdit", "WizardDuplicate",
            ]
        }

        static func apply(_ original: MemberWizardDraft, board: String) -> MemberWizardDraft {
            guard boards.contains(board) else { return original }
            let addingReturn = ["WizardEditReturn", "WizardEditReturnNoCredits", "WizardDiscardEdit"].contains(board)
            let returning = addingReturn || board == "WizardEditChanged"
            var draft = WizardCompletionBoardSeed.apply(original, board: "WizardReady")
            if returning {
                draft.form.addReturn()
                let index = draft.form.returnBoundary
                draft.form.legs[index].toIata = "AMS"
                draft.form.legs[index].toCity = "Amsterdam"
                draft.form.legs[index].departLocal = "2026-10-22T10:25"
                draft.form.legs[index].arriveLocal = "2026-10-22T15:30"
            }
            if board == "WizardDuplicate" {
                draft.form.clearDuplicateDates()
                draft.state.copiedRoute = "Amsterdam → " + (draft.airports["NRT"]?.city ?? "Tokyo")
                draft.state.step = .outbound
                draft.state.review = nil
                return draft
            }
            var review = draft.state.review
            review?.summary?.planEndDate =
                returning ? "2026-10-26" : board == "WizardEditWeb" ? "2026-10-22" : "2026-10-14"
            if returning {
                review?.summary?.line.key =
                    "We shift your clock :shift earlier, starting :count day before you leave. Your trip home is planned too.|We shift your clock :shift earlier, starting :count days before you leave. Your trip home is planned too."
            }
            var baseline = draft.form
            if addingReturn { baseline.removeReturn() }
            if board == "WizardEditNoReturn" {
                baseline.addReturn()
                baseline.legs[baseline.returnBoundary].toIata = "AMS"
            }
            if board == "WizardEditWeb" {
                draft.form.end.kind = "nights"
                draft.form.end.nights = 9
                baseline = draft.form
                draft.state.snapshotStayEnd = ApiStayEnd(
                    checkOutLocalDate: "2026-10-21", leaveUtc: "2026-10-21T03:00:00Z")
            }
            if board == "WizardEditWeb" { baseline.legs[0].seatWindow = "right" }
            if board == "WizardEditChanged" {
                baseline.legs[baseline.returnBoundary].departLocal = "2026-10-21T10:25"
                baseline.legs[baseline.returnBoundary].arriveLocal = "2026-10-21T15:30"
            }
            draft.state.edit = TripEditContext(tripID: "capture-trip", sourceRevision: "capture-source")
            draft.state.firstTrip = false
            draft.state.profile = JSONObject()
            draft.state.originalForm = baseline
            let current = draft.form
            draft.form = baseline
            draft.state.originalInput = draft.inputFingerprint
            draft.form = current
            draft.state.review = review
            if board == "WizardEditWeb" { draft.state.review?.summary?.stayEnd = draft.state.snapshotStayEnd }
            draft.state.review?.identity.sourceRevision = "capture-source"
            draft.form.identity = draft.state.review?.identity
            draft.state.review?.price?.state = returning ? .edit : .paid
            draft.state.review?.price?.cost = returning ? 1 : 0
            draft.state.review?.price?.balance = board == "WizardEditReturnNoCredits" ? 0 : 3
            draft.state.review?.canSave = board != "WizardEditReturnNoCredits"
            draft.state.review?.saveBlockedReason = board == "WizardEditReturnNoCredits" ? "Not enough credits" : nil
            draft.state.progressFloor = 0.95
            draft.state.returnToReady = true
            draft.state.returnRouteConfirmed = returning
            draft.state.entered = draft.hasChanges
            if board == "WizardEditChanged", let price = draft.state.review?.price {
                draft.state.sourceChange = WizardPresentation.SourceChange(
                    form: draft.form, fields: [.returnFlight], price: price, previousPrice: price)
            }
            if board == "WizardExcludedEdit" {
                draft.state.step = .excluded
                draft.state.review?.status = .noPlan
                draft.state.review?.summary = nil
                draft.state.review?.price = nil
                draft.state.review?.reasons = [
                    CopyLine(key: "This plan is not available for travellers under 18.", args: [])
                ]
            } else if ["WizardCheckingEdit", "WizardCheckOfflineEdit", "WizardCheckServerEdit"].contains(board) {
                draft.state.step = .checking
            } else {
                draft.state.step = .ready
            }
            return draft
        }
    }
#endif

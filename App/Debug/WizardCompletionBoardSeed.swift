#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import TripWizard

    enum WizardCompletionBoardSeed {
        static var sheets: [String: PromptKind] {
            [
                "WizardFineTuneSheet": .seatSide, "WizardSheet": .seatSide,
                "WizardSheetBlue": .blueBlockers, "WizardSheetBlueError": .blueBlockers,
                "WizardSheetBusy": .preDepartureBusyHours, "WizardSheetCheckout": .lateCheckOut,
                "WizardSheetDrinks": .cups, "WizardSheetDrinksError": .cups,
                "WizardSheetFreeSleep": .freeDayTimes, "WizardSheetLight": .lightDevice,
                "WizardSheetRoom": .room, "WizardSheetWake": .latestWake,
            ]
        }
        static func apply(_ original: MemberWizardDraft, board: String) -> MemberWizardDraft {
            guard board != "WizardSaveJourney" else { return original }
            guard
                board.hasPrefix("WizardFineTune") || board.hasPrefix("WizardReady") || board.hasPrefix("WizardSave")
                    || board == "WizardCalculating" || sheets[board] != nil
            else { return original }
            var draft = original
            if board == "WizardFineTuneMulti" || board == "WizardReadyReturn" {
                let stop = draft.airports["DXB"]!
                draft.form.insertStop(stop, beforeDestinationOf: 0)
                draft.form.legs[0].arriveLocal = "2026-10-12T23:25"
                draft.form.legs[1].departLocal = "2026-10-13T02:05"
                draft.form.legs[1].arriveLocal = "2026-10-13T16:35"
            }
            if ["WizardReadyReturn", "WizardReadyOneFree"].contains(board) || board == "WizardSheetCheckout" {
                draft.form.addReturn()
                let index = draft.form.returnBoundary
                draft.form.legs[index].toIata = "AMS"
                draft.form.legs[index].toCity = "Amsterdam"
                draft.form.legs[index].departLocal = "2026-10-22T10:25"
                draft.form.legs[index].arriveLocal = "2026-10-22T15:30"
                draft.state.returnRouteConfirmed = true
            }
            if board == "WizardFineTuneSleep" {
                draft.form.override.enabled = true
                draft.form.override.habitualBed = "00:30"
                draft.form.override.habitualWake = "08:30"
            }
            draft.form.preparation.latestWake = board == "WizardReadyAdjusted" ? "08:00" : "08:30"
            if board == "WizardSheetRoom" || board == "WizardFineTuneSleep" {
                draft.form.stays[0].bedAvailableMode = "declared"
                draft.form.stays[0].bedAvailableFromLocal = "2026-10-13T15:00"
            }
            if board == "WizardSheetBusy" {
                draft.form.preparation.busyAnswered = true
                draft.form.preparation.busyIntervals = [
                    WizardBusy(startLocal: "2026-10-09T09:00", endLocal: "2026-10-09T17:30"),
                    WizardBusy(startLocal: "2026-10-12T08:00", endLocal: "2026-10-12T11:00"),
                ]
            }
            if ["WizardSheet", "WizardFineTuneSheet", "WizardFineTune", "WizardFineTuneBusy", "WizardFineTuneMulti"]
                .contains(board)
            {
                draft.form.legs[0].seatWindow = "left"
            }
            let input = draft.form.reviewInput(identity: nil).input
            var profile = JSONObject([
                "freeDayStatus": .string("declared"), "freeDayBed": .string("00:30"), "freeDayWake": .string("09:00"),
                "lightDevice": .string("box"), "blueBlockers": .string("rated"),
                "blueBlockerMdfd": .string(board == "WizardSheetBlueError" ? "12" : "1.5"),
                "caffeineHabit": .string("cups"),
                "cupsFilterCoffee": .number(board == "WizardSheetDrinksError" ? 0 : 2),
            ])
            if board == "WizardFineTuneSleep" { profile["freeDayStatus"] = .string("same_as_workdays") }
            draft.state.savedProfile = profile
            for (field, value) in draft.state.profile.fields { profile[field] = value }
            var prompts = MockWizardPrompts.make(input: input, profile: profile)
            if ["WizardFineTune", "WizardFineTuneBusy", "WizardFineTuneMulti"].contains(board) {
                var withReturn = input
                withReturn.return = input.outbound
                if let checkout = MockWizardPrompts.make(input: withReturn, profile: profile).first(where: {
                    $0.kind == .lateCheckOut
                }) {
                    prompts.append(checkout)
                }
                let order: [PromptKind] =
                    board == "WizardFineTuneMulti"
                    ? [.room, .seatSide, .lateCheckOut, .latestWake]
                    : [.room, .latestWake, .seatSide, .lateCheckOut, .preDepartureBusyHours, .cups]
                prompts = order.flatMap { kind in prompts.filter { $0.kind == kind } }
                if board == "WizardFineTuneMulti" {
                    for index in prompts.indices where prompts[index].kind == .latestWake {
                        prompts[index].required = false
                    }
                }
            }
            if board == "WizardFineTuneSleep" {
                prompts = prompts.filter { [.room, .latestWake, .freeDayTimes].contains($0.kind) }
            }
            if board == "WizardFineTuneNone" { prompts = [] }
            let unlimited = board == "WizardReadyUnlimited"
            let free = board == "WizardReadyFree"
            let noCredits = board == "WizardReadyNoCredits"
            let identity = ApiReviewIdentity(token: "capture", inputRevision: 1, reviewRevision: 1, sourceRevision: nil)
            draft.form.identity = identity
            draft.state.review = ApiTripReview(
                identity: identity, status: board == "WizardReadyAdjusted" ? .modified : .ok,
                reasons: board == "WizardReadyAdjusted"
                    ? [
                        CopyLine(
                            key:
                                "You gave no latest wake-up time, so the plan wakes you at most an hour later than usual.",
                            args: [])
                    ] : [], prompts: prompts,
                summary: ApiReviewSummary(
                    line: CopyLine(
                        key:
                            "We shift your clock :shift earlier, starting :count day before you leave.|We shift your clock :shift earlier, starting :count days before you leave.",
                        args: [
                            .standard(CopyArg(name: "shift", kind: .minutes, value: .number(420))),
                            .standard(CopyArg(name: "count", kind: .count, value: .number(3))),
                        ]),
                    adaptation: AdaptationView(goal: .full, direction: .earlier, shiftMin: 420), preparationDays: 3,
                    planStartUtc: "2026-10-09T05:15:00Z", planStartZone: "Europe/Amsterdam", planEndDate: "2026-10-18",
                    endCopy: []),
                price: ApiReviewPrice(
                    state: unlimited ? .unlimited : free ? .free : .create,
                    cost: unlimited || free ? 0 : board == "WizardReadyReturn" ? 2 : 1, balance: noCredits ? 0 : 3,
                    unlimited: unlimited, freeDirections: board == "WizardReadyOneFree" ? [.return] : []),
                canSave: !noCredits, saveBlockedReason: noCredits ? "Not enough credits" : nil,
                itinerary: ApiReviewItinerary(legs: [], layovers: []))
            draft.state.reviewedAt = Date()
            draft.state.lastInputStep = .returnChoice
            draft.state.step =
                board.hasPrefix("WizardFineTune") || sheets[board] != nil
                ? .fineTune : board == "WizardCalculating" ? .calculating : .ready
            if let kind = sheets[board] { draft.state.promptSheetID = prompts.first { $0.kind == kind }?.id }
            if board == "WizardSaveOffline" { draft.state.saveFailure = WizardSaveFailure(kind: .offline) }
            if board == "WizardSaveServer" { draft.state.saveFailure = WizardSaveFailure(kind: .server) }
            if board == "WizardSaveThrottle" {
                draft.state.saveFailure = WizardSaveFailure(kind: .throttle, retryAt: Date().addingTimeInterval(42))
            }
            return draft
        }
    }
#endif

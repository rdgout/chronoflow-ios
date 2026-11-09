#if DEBUG
    import AppCore
    import Foundation
    import TripWizard

    enum WizardBoardCaptureSeed {
        static func draft(_ original: MemberWizardDraft, board: String, locale: Locale) -> MemberWizardDraft {
            var draft = original
            let dutch = locale.language.languageCode?.identifier == "nl"
            let airports = [
                ApiAirportSuggestion(
                    iata: "AMS", name: "Amsterdam Airport Schiphol", city: "Amsterdam", country: "NL",
                    timezone: "Europe/Amsterdam"),
                ApiAirportSuggestion(
                    iata: "NRT", name: "Narita International", city: dutch ? "Tokio" : "Tokyo", country: "JP",
                    timezone: "Asia/Tokyo"),
                ApiAirportSuggestion(
                    iata: "DXB", name: "Dubai International", city: "Dubai", country: "AE", timezone: "Asia/Dubai"),
                ApiAirportSuggestion(
                    iata: "BKK", name: "Suvarnabhumi", city: "Bangkok", country: "TH", timezone: "Asia/Bangkok"),
            ]
            draft.airports = Dictionary(uniqueKeysWithValues: airports.map { ($0.iata, $0) })
            draft.form = WizardForm()
            draft.form.legs[0].fromIata = "AMS"
            draft.form.legs[0].fromCity = "Amsterdam"
            draft.form.legs[0].toIata = "NRT"
            draft.form.legs[0].toCity = airports[1].city
            draft.form.legs[0].departLocal = "2026-10-12T14:40"
            draft.form.legs[0].arriveLocal = "2026-10-13T09:15"
            draft.state.entered = true
            draft.state.fromLastTrip = false
            draft.state.sleepNeeded = false
            draft.state.profile = JSONObject([
                "habitual_bed": .string("23:30"), "habitual_wake": .string("07:15"),
                "chronotype": .string("intermediate"),
            ])
            draft.state.step = .outbound
            if board.hasPrefix("WizardWhere") || board == "WizardAirportFrom" {
                draft.state.step = .whereTo
                draft.state.fromLastTrip = board == "WizardWhere" || board == "WizardWhereSame"
                if board == "WizardWhereEmpty" || board == "WizardAirportFrom" {
                    draft.form = WizardForm()
                    draft.state.entered = false
                } else if board == "WizardWhereSame" {
                    draft.form.legs[0].toIata = "AMS"
                    draft.form.legs[0].toCity = "Amsterdam"
                }
            }
            if ["WizardWhereStop", "WizardWhereStops", "WizardWhereLimit", "WizardStopSearchSecond"].contains(board) {
                draft.state.step = .whereTo
                draft.state.fromLastTrip = true
                draft.form.insertStop(airports[2], beforeDestinationOf: 0)
                if board == "WizardWhereStops" { draft.form.insertStop(airports[3], beforeDestinationOf: 1) }
                if board == "WizardWhereLimit" {
                    while draft.form.legs.count < WizardForm.maxFlights {
                        draft.form.insertStop(
                            airports[draft.form.legs.count.isMultiple(of: 2) ? 3 : 2],
                            beforeDestinationOf: draft.form.returnBoundary - 1)
                    }
                }
                for index in draft.form.legs.indices {
                    draft.form.legs[index].departLocal = ""
                    draft.form.legs[index].arriveLocal = ""
                }
            }
            if board == "WizardStopSearch" { draft.state.step = .whereTo }
            if board == "WizardOutboundEmpty" {
                draft.form.legs[0].departLocal = ""
                draft.form.legs[0].arriveLocal = ""
            }
            if board == "WizardOutboundErrors" {
                draft.form.legs[0].arriveLocal = "2026-10-11T09:15"
                draft.fieldErrors["legs.0.arriveLocal"] = FieldMessage(key: "Check the departure and arrival times.")
            }
            if [
                "WizardOutboundStop", "WizardOutboundStopNew", "WizardOutboundStopEmpty", "WizardOutboundOvernight",
                "WizardOutboundThree", "WizardOutboundTwoErrors", "WizardOutboundScrollErrors",
            ].contains(board) {
                draft.form.insertStop(airports[2], beforeDestinationOf: 0)
                if board != "WizardOutboundStopNew" && board != "WizardOutboundStopEmpty" {
                    draft.form.legs[0].arriveLocal =
                        board == "WizardOutboundOvernight" ? "2026-10-12T22:25" : "2026-10-12T23:25"
                    draft.form.legs[1].departLocal =
                        board == "WizardOutboundOvernight" ? "2026-10-14T02:05" : "2026-10-13T02:05"
                    draft.form.legs[1].arriveLocal =
                        board == "WizardOutboundOvernight" ? "2026-10-14T16:35" : "2026-10-13T16:35"
                }
            }
            if board == "WizardOutboundStopEmpty" { draft.form.legs[0].departLocal = "" }
            if board == "WizardOutboundThree" {
                draft.form.insertStop(airports[3], beforeDestinationOf: 1)
                draft.form.legs[1].arriveLocal = "2026-10-13T11:20"
            }
            if board == "WizardOutboundTwoErrors" {
                draft.form.legs[1].arriveLocal = "2026-10-12T16:35"
                draft.fieldErrors["legs.1.arriveLocal"] = FieldMessage(key: "Check the departure and arrival times.")
            }
            if board == "WizardOutboundScrollErrors" {
                draft.form.insertStop(airports[3], beforeDestinationOf: 1)
                draft.form.insertStop(airports[2], beforeDestinationOf: 2)
                draft.form.insertStop(airports[3], beforeDestinationOf: 3)
                draft.form.legs[0].arriveLocal = "2026-10-11T23:25"
                draft.form.legs[1].arriveLocal = "2026-10-13T11:20"
                draft.form.legs[2].departLocal = "2026-10-13T13:00"
                draft.form.legs[2].arriveLocal = "2026-10-13T17:00"
                draft.form.legs[3].departLocal = "2026-10-13T19:00"
                draft.form.legs[3].arriveLocal = "2026-10-14T04:00"
                draft.form.legs[4].departLocal = "2026-10-14T03:00"
                draft.form.legs[4].arriveLocal = "2026-10-14T14:30"
                draft.fieldErrors["legs.0.arriveLocal"] = FieldMessage(key: "Check the departure and arrival times.")
                draft.fieldErrors["legs.4.departLocal"] = FieldMessage(
                    key: "This flight leaves before the previous one lands.")
            }
            if board == "WizardReturn" || board == "WizardReturnWeb" {
                draft.state.step = .returnChoice
                if board == "WizardReturnWeb" {
                    draft.form.end.kind = "nights"
                    draft.form.end.nights = 9
                }
            }
            if board.hasPrefix("WizardReturnFlight") || board == "WizardAirportHome"
                || board.hasPrefix("WizardHomeRoute") || board == "WizardStopSearchHome"
            {
                draft.form.addReturn()
                draft.form.legs[1].toIata = "AMS"
                draft.form.legs[1].toCity = "Amsterdam"
                draft.state.step = .returnFlight
                draft.state.returnRouteConfirmed = true
                if board.hasPrefix("WizardHomeRoute") || board == "WizardAirportHome" || board == "WizardStopSearchHome"
                {
                    draft.state.step = .returnRoute
                    draft.state.returnRouteConfirmed = false
                    if board == "WizardHomeRouteStop" { draft.form.insertStop(airports[2], beforeDestinationOf: 1) }
                }
                if board == "WizardReturnFlightPast" {
                    draft.form.legs[1].departLocal = "2026-10-22T10:25"
                    draft.form.legs[1].arriveLocal = "2026-10-22T15:30"
                    draft.fieldErrors["review"] = FieldMessage(
                        key: "A new plan needs an upcoming arrival. Check your flight dates.")
                }
            }
            if board == "WizardOutboundPast" {
                draft.form.legs[0].departLocal = "2026-09-02T14:40"
                draft.form.legs[0].arriveLocal = "2026-09-03T09:15"
                draft.fieldErrors["review"] = FieldMessage(
                    key: "A new plan needs an upcoming arrival. Check your flight dates or add your return flight.")
            }
            if board == "WizardSleep" {
                draft.state.sleepNeeded = true
                draft.state.step = .sleep
            }
            if board.hasPrefix("WizardCheck") {
                draft.state.step = .checking
                draft.state.lastInputStep = .returnChoice
                draft.state.checkingAnswers = board == "WizardCheckingAgain"
            }
            let questions = [
                ("WizardQAge", "age_band", "Which age group are you in?"),
                ("WizardQBipolar", "bipolar", "Do you have bipolar disorder?"),
                ("WizardQPregnant", "pregnancy", "Are you pregnant or breastfeeding?"),
                (
                    "WizardQShift", "shift_work",
                    "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?"
                ),
                ("WizardQCaffeine", "caffeine_ruled_out", "Have you been told to avoid caffeine?"),
                (
                    "WizardQEye", "eye_disease",
                    "Do you have an eye disease, or take medicine that makes your eyes sensitive to light?"
                ),
                (
                    "WizardQClot", "vte",
                    "Do you have a risk factor for blood clots, such as a past clot or a clotting disorder?"
                ),
            ]
            if let (_, field, key) = questions.first(where: { $0.0 == board }) {
                let age = field == "age_band"
                draft.state.step = .question
                draft.state.questionIndex = 0
                draft.state.questions = [
                    ApiReviewPrompt(
                        id: field, kind: age ? .ageBand : .screening, blocking: true, required: true,
                        text: CopyLine(key: key, args: []), scope: ApiReviewPromptScope(), target: .profile,
                        fields: [field], answer: [:],
                        shape: ApiReviewPromptShape(
                            kind: age ? .options : .boolean, options: age ? ["under_18", "18_64", "65_plus"] : []))
                ]
            }
            if board.hasPrefix("WizardExcluded") {
                draft.state.step = .excluded
                let shift = board == "WizardExcludedShift"
                draft.state.profile[shift ? "shift_work" : "age_band"] = shift ? .bool(true) : .string("under_18")
                draft.state.review = ApiTripReview(
                    identity: ApiReviewIdentity(
                        token: "capture", inputRevision: 1, reviewRevision: 1, sourceRevision: "capture"),
                    status: .noPlan,
                    reasons: [
                        CopyLine(
                            key: shift
                                ? "This plan is not available if, in the past 14 days, you have worked night or rotating shifts or had a very irregular sleep schedule."
                                : "This plan is not available for travellers under 18.", args: [])
                    ],
                    prompts: [],
                    price: ApiReviewPrice(state: .free, cost: 0, balance: 3, unlimited: false, freeDirections: []),
                    canSave: false,
                    itinerary: ApiReviewItinerary(legs: [], layovers: []))
            }
            return WizardCompletionBoardSeed.apply(draft, board: board)
        }

        static func freeze(_ model: MemberWizardModel, board: String) {
            if [.fineTune, .ready, .calculating].contains(model.draft.state.step) {
                model.freezeCompletionBoard(
                    reviewing: board == "WizardFineTuneBusy" || board == "WizardReadyChecking",
                    answerError: board == "WizardSheetBlueError"
                        ? "Enter a rating between 0.1 and 9.9."
                        : board == "WizardSheetDrinksError" ? "Add at least one drink to save this answer." : nil,
                    retry: board == "WizardSaveThrottle" ? 42 : 0)
            }
            let failure: DataFailure? =
                board == "WizardCheckOffline"
                ? .offline
                : board == "WizardCheckServer"
                    ? .server(status: 500)
                    : board == "WizardCheckThrottle" ? .throttled(retryAfterSeconds: 42, status: 429) : nil
            if model.draft.state.step == .checking {
                model.freezeBoardCapture(
                    ticks: 2, slow: board == "WizardCheckingSlow", failure: failure,
                    retry: board == "WizardCheckThrottle" ? 42 : 0)
            }
        }
    }
#endif

import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct WizardSearchTests {
    @Test func debouncesAndPacesRequestsAcrossSheetsBelowSixtyPerMinute() async throws {
        let clock = WizardTestClock()
        let requests = WizardSearchProbe()
        let service = AirportSearchService(
            search: { query in
                await requests.record(query, at: clock.now)
                return []
            }, now: { clock.now },
            sleep: { seconds in
                #expect(seconds > 0)
                clock.advance(seconds)
            })
        for query in ["", "A", String(repeating: "A", count: 61)] {
            #expect(try await service.results(for: query).isEmpty)
        }
        for _ in 0..<65 { _ = try await service.results(for: " AMS ") }
        let sent = await requests.times
        #expect(await requests.queries.allSatisfy { $0 == "AMS" })
        #expect(sent.count == 65)
        #expect(abs((sent.first?.timeIntervalSince(Date(timeIntervalSince1970: 1_800_000_000)) ?? 0) - 0.35) < 0.0001)
        for index in 1..<sent.count { #expect(sent[index].timeIntervalSince(sent[index - 1]) >= 1.019) }
        for date in sent { #expect(sent.filter { $0 >= date && $0 < date.addingTimeInterval(60) }.count <= 60) }
    }

    @Test func cancelledDebounceNeverMakesRequest() async throws {
        let requests = WizardSearchProbe()
        let gate = GenerationGate()
        let service = AirportSearchService(
            search: { query in
                await requests.record(query, at: Date())
                return []
            }, now: { Date() },
            sleep: { _ in
                await gate.open()
                try await Task.sleep(for: .seconds(3600))
            })
        let task = Task { try await service.results(for: "AMS") }
        await gate.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await requests.times.isEmpty)
    }

    @Test func serverThrottleSetsSharedWait() async throws {
        let clock = WizardTestClock()
        let requests = WizardSearchProbe()
        let service = AirportSearchService(
            search: { query in
                await requests.record(query, at: clock.now)
                if await requests.times.count == 1 { throw DataFailure.throttled(retryAfterSeconds: 42, status: 429) }
                return []
            }, now: { clock.now }, sleep: { clock.advance($0) })
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 42, status: 429)) {
            try await service.results(for: "AMS")
        }
        _ = try await service.results(for: "HND")
        let times = await requests.times
        #expect(times[1].timeIntervalSince(times[0]) >= 42)
    }
}

actor WizardSearchProbe {
    var queries: [String] = []
    var times: [Date] = []
    func record(_ query: String, at: Date) {
        queries.append(query)
        times.append(at)
    }
}

@Suite struct WizardPresentationTests {
    @Test func planDatesCountAndSourceChangesUseThePlanStartZone() throws {
        let locale = Locale(identifier: "en_GB")
        let translate: WizardPresentation.Translate = { key, values in
            values.reduce(key) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
        }
        let form = try WizardForm(input: generationInput())
        let review = try generationReview()
        #expect(WizardPresentation.planDayCount(review.summary) == 15)
        let dates = WizardPresentation.planDateSummary(form, summary: review.summary, locale: locale, t: translate)
        #expect(dates.contains("Sat 7 Nov") && dates.contains("Sat 21 Nov") && dates.hasSuffix("one way"))
        #expect(WizardPresentation.planDayCount(nil) == nil)
        #expect(WizardPresentation.planDateSummary(form, summary: nil, locale: locale, t: translate).isEmpty)
        let change = WizardPresentation.SourceChange(
            form: form, fields: [.route, .flight, .returnFlight, .sleep, .extras], price: review.price,
            previousPrice: review.price)
        let summary = try WizardPresentation.sourceChangeSummary(
            change, review: nil, stayEnd: nil, locale: locale, t: translate)
        let text = try #require(summary)
        #expect(text.contains("route changed to AMS → HND"))
        #expect(text.contains("trip end changed to One way"))
        #expect(text.contains("usual sleep times") && text.contains("3 days prep"))
        #expect(text.hasSuffix("The price is still 1 credits."))
        #expect(
            try WizardPresentation.sourceChangeSummary(
                .init(form: form, fields: [], price: nil), review: nil, stayEnd: nil, locale: locale, t: translate)
                == nil)
    }

    @Test func localFactsBeforeCheckingUseZonesAndCompleteNights() throws {
        var form = try WizardForm(input: generationInput())
        let airports = [
            "AMS": wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            "HND": wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"),
            "DXB": wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai"),
        ]
        form.legs[0].departLocal = "2026-10-12T14:40"
        form.legs[0].arriveLocal = "2026-10-13T09:15"
        #expect(form.itinerary == nil)
        #expect(WizardOutboundRules.flightMinutes(form: form, index: 0, airports: airports) == 695)
        form.legs[0].arriveLocal = "2026-10-11T09:15"
        #expect(WizardOutboundRules.flightMinutes(form: form, index: 0, airports: airports) == nil)
        form.insertStop(airports["DXB"]!, beforeDestinationOf: 0)
        form.legs[0].arriveLocal = "2026-10-12T23:25"
        form.legs[1].departLocal = "2026-10-13T02:05"
        let connection = WizardOutboundRules.connection(
            form: form, index: 1, airports: airports, duration: { String($0) })
        #expect(connection?.arguments["duration"] == .string("160"))
        form.legs[0].arriveLocal = "2026-10-12T22:25"
        form.legs[1].departLocal = "2026-10-14T02:05"
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, airports: airports, duration: { String($0) })?
                .arguments["count"] == .number(1))
        form.legs[0].toIata = "AMS"
        form.legs[1].fromIata = "AMS"
        form.legs[0].arriveLocal = "2026-10-24T23:00"
        form.legs[1].departLocal = "2026-10-25T07:00"
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, airports: airports, duration: { String($0) })?
                .arguments["count"] == .number(1))
        form.legs[0].arriveLocal = "2026-10-24T23:01"
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, airports: airports, duration: { String($0) })?.key
                == "Connection in {{airport}} · {{duration}}")
    }

    @Test func errorsPastConnectionsAndOvernightUseAirportClock() throws {
        var form = try WizardForm(input: generationInput())
        let airports = [
            "AMS": wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            "HND": wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"),
        ]
        form.legs[0].arriveLocal = "2026-11-09T09:00"
        #expect(
            WizardOutboundRules.errors(form: form, airports: airports, now: Date(), checkPast: false)[
                "legs.0.arriveLocal"]?.key == "Check the departure and arrival times.")
        form.legs[0].arriveLocal = "2026-11-11T09:00"
        let after = WizardDateTime.date("2026-11-12T12:00")!
        #expect(WizardOutboundRules.errors(form: form, airports: airports, now: after, checkPast: false).isEmpty)
        #expect(
            WizardOutboundRules.errors(form: form, airports: airports, now: after, checkPast: true)["review"]?.key
                == "A new plan needs an upcoming arrival. Check your flight dates or add your return flight.")
        form.insertStop(wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai"), beforeDestinationOf: 0)
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, duration: { String($0) })?.key == "Stop in {{airport}}"
        )
        form.itinerary = ApiReviewItinerary(
            legs: [],
            layovers: [
                ApiReviewLayover(journey: .outbound, afterLegIndex: 0, kind: .connection, durationMin: 160, nights: 0)
            ])
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, duration: { String($0) })?.key
                == "Connection in {{airport}} · {{duration}}")
        form.itinerary = ApiReviewItinerary(
            legs: [],
            layovers: [
                ApiReviewLayover(journey: .outbound, afterLegIndex: 0, kind: .stopover, durationMin: 1600, nights: 2)
            ])
        #expect(
            WizardOutboundRules.connection(form: form, index: 1, duration: { String($0) })?.arguments["count"]
                == .number(2))
    }

    @Test func summariesAndPromptAnswersRetainScopeAndFallback() throws {
        var form = try WizardForm(input: generationInput())
        let en = Locale(identifier: "en_GB")
        let translate: WizardPresentation.Translate = { key, values in
            values.reduce(key) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
        }
        #expect(WizardPresentation.flightSummary(form, locale: en, t: translate).contains("11:00 → Wed 06:00"))
        #expect(WizardPresentation.returnSummary(form, stayEnd: nil, locale: en, t: translate) == "One way")
        form.end.kind = "nights"
        form.end.nights = 9
        #expect(WizardPresentation.returnSummary(form, stayEnd: nil, locale: en, t: translate) == "9 nights")
        form.end.kind = "check_out"
        form.end.checkOutDate = "2026-11-21"
        #expect(WizardPresentation.returnSummary(form, stayEnd: nil, locale: en, t: translate).hasPrefix("Check-out"))
        var prompt = ApiReviewPrompt(
            id: "room", kind: .room, blocking: false, required: false, text: CopyLine(key: "Room?", args: []),
            scope: ApiReviewPromptScope(journey: .outbound, stayIndex: 0), target: .trip,
            fields: ["stay.bed_available_mode"], answer: ["stay.bed_available_mode": .string("arrival")],
            shape: ApiReviewPromptShape(kind: .options, options: ["arrival", "declared"]))
        #expect(
            try WizardPresentation.promptAnswerText(
                prompt, input: form.reviewInput(identity: nil), locale: en, t: translate) == "When I land")
        #expect(WizardPresentation.promptKey(prompt).contains("room:Room?:0:"))
        prompt.target = .profile
        prompt.kind = .cups
        prompt.fields = ["caffeine_use"]
        prompt.answer = ["caffeine_use": .string("non_user")]
        #expect(
            try WizardPresentation.promptAnswerText(
                prompt, input: form.reviewInput(identity: nil), locale: en, t: translate) == "None")
        let input = form.reviewInput(
            identity: nil,
            profile: JSONObject([
                "caffeine_use": .string("user"), "cups_filter_coffee": .number(2), "cups_tea": .number(1),
            ]))
        prompt.fields += ["cups_filter_coffee", "cups_tea"]
        #expect(try WizardPresentation.promptAnswerText(prompt, input: input, locale: en, t: translate) == "3 a day")
        #expect(
            WizardPresentation.promptFieldError(
                prompt, form: form, errors: ["profile.cupsTea": FieldMessage(key: "error")])?.key == "error")
        #expect(
            try WizardPresentation.extrasSummary(form, review: nil, input: input, locale: en, t: translate)
                == "3 days prep")
    }
}

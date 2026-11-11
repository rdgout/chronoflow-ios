import AppCore
import CryptoKit
import Foundation

struct MockWizardDraft: Codable, Sendable, Equatable {
    var owner: String
    var tripID: String?
    var input: ApiTripInput
    var review: ApiTripReview
    var profile: JSONObject
    var expiresAt: TimeInterval
}

struct MockWizardReceipt: Codable, Sendable, Equatable {
    var intent: String
    var tripID: String
    var expiresAt: TimeInterval
}

enum MockTripGeneration {
    static func airports() throws -> [ApiAirportSuggestion] {
        let names = [
            "AMS": ("Amsterdam Airport Schiphol", "NL"), "HND": ("Tokyo Haneda Airport", "JP"),
            "JFK": ("John F. Kennedy International Airport", "US"), "SIN": ("Singapore Changi Airport", "SG"),
            "SYD": ("Sydney Kingsford Smith Airport", "AU"), "LHR": ("London Heathrow Airport", "GB"),
            "DXB": ("Dubai International Airport", "AE"), "LAX": ("Los Angeles International Airport", "US"),
        ]
        var airports: [String: ApiAirportSuggestion] = [:]
        for airport in try MockTripFixtures.templates().flatMap({ $0.detail.trip.legs.flatMap { [$0.from, $0.to] } }) {
            guard let name = names[airport.iata] else { continue }
            airports[airport.iata] = ApiAirportSuggestion(
                iata: airport.iata, name: name.0, city: airport.city, country: name.1, timezone: airport.zone)
        }
        return airports.values.sorted { $0.iata < $1.iata }
    }

    static func instant(_ local: String, airport: ApiAirportSuggestion) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: airport.timezone)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.isLenient = false
        guard let date = formatter.date(from: local), formatter.string(from: date) == local else {
            throw DataFailure.validation(
                fields: ["review": FieldMessage(key: "Check the departure and arrival times.")], status: 422)
        }
        return date
    }

    static func itinerary(_ input: ApiTripInput) throws -> ApiReviewItinerary {
        let airports = try airports()
        var legs: [ApiReviewLeg] = []
        for (direction, journey) in [(TripDirection.outbound, input.outbound), (.return, input.return)] {
            guard let journey else { continue }
            guard !journey.legs.isEmpty else {
                throw DataFailure.validation(
                    fields: [direction.rawValue + ".legs": FieldMessage(key: "Please fill this in.")], status: 422)
            }
            for (index, leg) in journey.legs.enumerated() {
                let prefix = "\(direction.rawValue).legs.\(index)"
                guard let from = airports.first(where: { $0.iata == leg.fromIata }) else {
                    throw DataFailure.validation(
                        fields: [
                            prefix + ".from_iata": FieldMessage(key: "Choose an airport from the search results.")
                        ],
                        status: 422)
                }
                guard let to = airports.first(where: { $0.iata == leg.toIata }) else {
                    throw DataFailure.validation(
                        fields: [prefix + ".to_iata": FieldMessage(key: "Choose an airport from the search results.")],
                        status: 422)
                }
                let depart = try instant(leg.departLocal, airport: from)
                let arrive = try instant(leg.arriveLocal, airport: to)
                guard arrive > depart else {
                    throw DataFailure.validation(
                        fields: [prefix + ".arrive_local": FieldMessage(key: "Check the departure and arrival times.")],
                        status: 422)
                }
                legs.append(
                    ApiReviewLeg(
                        journey: direction, legIndex: index, departUtc: depart.ISO8601Format(),
                        arriveUtc: arrive.ISO8601Format(), flightMin: Int(arrive.timeIntervalSince(depart) / 60)))
            }
        }
        return ApiReviewItinerary(legs: legs, layovers: try layovers(input, legs: legs, airports: airports))
    }

    static func template(_ input: ApiTripInput) throws -> MockTripFixtures.Template {
        let templates = try MockTripFixtures.templates()
        guard let first = input.outbound.legs.first else { throw DataFailure.reviewExpired }
        let allLegs = input.outbound.legs + (input.return?.legs ?? [])
        func score(_ template: MockTripFixtures.Template) -> Int {
            let matches =
                template.detail.trip.legs.map {
                    Int($0.from.iata == first.fromIata ? 1 : 0) + Int($0.to.iata == first.toIata ? 1 : 0)
                }.max() ?? 0
            let others = allLegs.dropFirst().filter { leg in
                template.detail.trip.legs.contains { $0.from.iata == leg.fromIata && $0.to.iata == leg.toIata }
            }.count
            return matches * 100 + others
        }
        let template = templates.dropFirst().reduce(templates[0]) { score($1) > score($0) ? $1 : $0 }
        let airports = try airports()
        guard let airport = airports.first(where: { $0.iata == first.fromIata }) else {
            throw DataFailure.reviewExpired
        }
        let target = try instant(first.departLocal, airport: airport)
        let original = try instant(
            template.card.departLocal,
            airport: ApiAirportSuggestion(
                iata: template.card.from.iata, name: "", city: template.card.from.city, country: "",
                timezone: template.card.from.zone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: airport.timezone)!
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: original), to: calendar.startOfDay(for: target)
        ).day!
        let moved = calendar.date(byAdding: .day, value: days, to: original)!
        return try MockTripFixtures.rebase(template, days: days, minutes: Int(target.timeIntervalSince(moved) / 60))
    }

    static func prompts(_ profile: JSONObject) -> [ApiReviewPrompt] {
        let fields = [
            ("age_band", "Which age group are you in?"),
            (
                "shift_work",
                "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?"
            ),
            ("bipolar", "Do you have bipolar disorder?"),
            ("eye_disease", "Do you have an eye disease, or take medicine that makes your eyes sensitive to light?"),
            ("pregnancy", "Are you pregnant or breastfeeding?"),
            ("caffeine_ruled_out", "Have you been told to avoid caffeine?"),
            ("vte", "Do you have a risk factor for blood clots, such as a past clot or a clotting disorder?"),
        ]
        return fields.compactMap { field, text in
            let value = profile[TripWizardErrors.camel(field)] ?? .null
            guard value == .null || value == .string("unanswered") else { return nil }
            let age = field == "age_band"
            return ApiReviewPrompt(
                id: age ? "age_band:::" : "screening:\(field)::", kind: age ? .ageBand : .screening, blocking: true,
                required: true, text: CopyLine(key: text, args: []), scope: ApiReviewPromptScope(), target: .profile,
                fields: [field], answer: [field: value],
                shape: ApiReviewPromptShape(
                    kind: age ? .options : .boolean, options: age ? ["under_18", "18_64", "65_plus"] : []))
        }
    }

    static func review(
        _ input: ApiTripInput, identity: ApiReviewIdentity, settings: AccountSettings, edit: Bool,
        paidDirections: [TripDirection]
    ) throws
        -> ApiTripReview
    {
        let itinerary = try itinerary(input)
        let template = try template(input)
        let profile = settings.bodyClock
        let excluded = profile["ageBand"] == .string("under_18") || profile["shiftWork"] == .bool(true)
        let blocking = excluded ? [] : prompts(profile)
        let prompts =
            excluded ? [] : blocking.isEmpty ? MockWizardPrompts.make(input: input, profile: profile) : blocking
        let status: PlanStatus = excluded ? .noPlan : blocking.isEmpty ? template.detail.plan.status : .needsAnswers
        let planned = status == .ok || status == .modified
        let unlimited = settings.planCredits["unlimited"] == .bool(true)
        let balance: Int
        if case .number(let value) = settings.planCredits["credits"] {
            balance = NSDecimalNumber(decimal: value).intValue
        } else {
            balance = 0
        }
        let directions: [TripDirection] = input.return == nil ? [.outbound] : [.outbound, .return]
        let free = template.detail.plan.summary?.adaptation.goal == .routine
        let cost = unlimited || free ? 0 : directions.filter { !paidDirections.contains($0) }.count
        let price = ApiReviewPrice(
            state: unlimited ? .unlimited : cost == 0 ? (edit ? .paid : .free) : (edit ? .edit : .create), cost: cost,
            balance: balance,
            unlimited: unlimited, freeDirections: free ? directions : [])
        let plan = template.detail.plan
        let summary: ApiReviewSummary?
        if planned, let value = plan.summary, let first = plan.days.first, let last = plan.days.last {
            summary = ApiReviewSummary(
                line: summaryLine(value, withReturn: input.return != nil), adaptation: value.adaptation,
                preparationDays: value.preparation.emitted, planStartUtc: first.startUtc,
                planStartZone: first.zones.first?.tz ?? template.card.from.zone, planEndDate: last.labelDate,
                endCopy: value.endCopy, stayEnd: try stayEnd(input))
        } else {
            summary = nil
        }
        let reasons: [CopyLine]
        if excluded {
            reasons = [
                CopyLine(
                    key: profile["ageBand"] == .string("under_18")
                        ? "This plan is not available for travellers under 18."
                        : "This plan is not available if, in the past 14 days, you have worked night or rotating shifts or had a very irregular sleep schedule.",
                    args: [])
            ]
        } else if !blocking.isEmpty {
            reasons = [CopyLine(key: "Answer the health questions to get your plan.", args: [])]
        } else {
            reasons = plan.reasons
        }
        return ApiTripReview(
            identity: identity, status: status, reasons: reasons, prompts: prompts, summary: summary, price: price,
            canSave: planned && balance >= cost,
            saveBlockedReason: planned && balance < cost ? "Not enough credits" : nil, itinerary: itinerary)
    }

    static func saved(_ draft: MockWizardDraft, tripID: String) throws -> (
        TripListItem, TripDetail, ApiTripInputSnapshot
    ) {
        let template = try template(draft.input)
        var card = template.card
        var detail = template.detail
        let airports = try airports()
        let lookup = Dictionary(uniqueKeysWithValues: airports.map { ($0.iata, $0) })
        func ref(_ iata: String) throws -> AirportRef {
            guard let airport = lookup[iata] else { throw DataFailure.reviewExpired }
            return AirportRef(iata: iata, city: airport.city, zone: airport.timezone)
        }
        let input = draft.input
        let legs = input.outbound.legs + (input.return?.legs ?? [])
        guard let first = legs.first, let outboundLast = input.outbound.legs.last, let start = detail.plan.days.first,
            let end = detail.plan.days.last
        else { throw DataFailure.reviewExpired }
        card.id = tripID
        card.from = try ref(first.fromIata)
        card.to = try ref(outboundLast.toIata)
        card.departLocal = first.departLocal
        card.arriveLocal = outboundLast.arriveLocal
        card.departureUtc = draft.review.itinerary.legs.first!.departUtc
        card.arrivalUtc = draft.review.itinerary.legs[input.outbound.legs.count - 1].arriveUtc
        card.flightNumber = first.flightNumber
        card.connections = try input.outbound.legs.dropLast().map { try ref($0.toIata) }
        card.progress = TripProgress(status: .upcoming)
        detail.trip = TripDetailView(
            id: tripID, from: card.from, to: card.to, departLocal: card.departLocal, departureUtc: card.departureUtc,
            endUtc: end.endUtc, offsetDifferenceMin: card.offsetDifferenceMinutes,
            legs: try legs.enumerated().map { index, leg in
                TripDetailLegView(
                    position: index, flightNumber: leg.flightNumber, from: try ref(leg.fromIata),
                    to: try ref(leg.toIata), returnLeg: index >= input.outbound.legs.count)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let material = try encoder.encode(draft.input) + encoder.encode(draft.review.identity)
        let hash = SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
        detail.plan.meta.inputHash = hash
        detail.checkState.planInputHash = hash
        detail.detailVersion = hash
        detail.checkState.marks = []
        let item = TripListItem(
            card: card, planInputHash: detail.plan.meta.inputHash, planStartUtc: start.startUtc,
            planStartZone: start.zones.first!.tz, planEndUtc: end.endUtc, planEndDate: end.labelDate,
            preparationDays: detail.plan.summary?.preparation.emitted ?? 0, adaptation: detail.plan.summary?.adaptation,
            keepOffline: true, detailVersion: detail.detailVersion, checkState: detail.checkState)
        let used = Set(legs.flatMap { [$0.fromIata, $0.toIata] })
        let snapshot = ApiTripInputSnapshot(
            input: input, sourceRevision: detail.plan.meta.inputHash, airports: lookup.filter { used.contains($0.key) },
            stayEnd: try stayEnd(input))
        return (item, detail, snapshot)
    }
}

extension MockTripGeneration {
    static func snapshot(_ detail: TripDetail) throws -> ApiTripInputSnapshot {
        let airports = try airports()
        let lookup = Dictionary(uniqueKeysWithValues: airports.map { ($0.iata, $0) })
        func local(_ utc: String, zone: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: zone)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let normalized = utc.count == 17 ? utc.replacingOccurrences(of: "Z", with: ":00Z") : utc
            return formatter.string(from: ISO8601DateFormatter().date(from: normalized)!)
        }
        var outbound: [ApiTripInputLeg] = []
        var returning: [ApiTripInputLeg] = []
        let flights = detail.plan.blocks.filter { $0.type == .flight }
        for leg in detail.trip.legs {
            guard
                let flight = flights.first(where: { block in
                    if case .flight(let params) = block.params { return params.legIndex == leg.position }
                    return false
                })
            else { continue }
            let input = ApiTripInputLeg(
                fromIata: leg.from.iata, toIata: leg.to.iata, departLocal: local(flight.startUtc, zone: leg.from.zone),
                arriveLocal: local(flight.endUtc, zone: leg.to.zone), flightNumber: leg.flightNumber,
                seatLieFlat: false, stay: ApiTripInputStay(lateCheckOutOrDayRoom: false, busyIntervals: []))
            if leg.returnLeg { returning.append(input) } else { outbound.append(input) }
        }
        let input = ApiTripInput(
            outbound: ApiTripInputJourney(legs: outbound),
            return: returning.isEmpty ? nil : ApiTripInputJourney(legs: returning),
            tripEndKind: returning.isEmpty ? "one_way" : "return_legs",
            preparationDays: detail.plan.summary?.preparation.emitted ?? 0, fastDelayOptIn: false,
            override: ApiTripInputOverride(use: false), preDepartureBusyAnswered: false, preDepartureBusyIntervals: [])
        let used = Set(detail.trip.legs.flatMap { [$0.from.iata, $0.to.iata] })
        return ApiTripInputSnapshot(
            input: input, sourceRevision: detail.plan.meta.inputHash, airports: lookup.filter { used.contains($0.key) })
    }
}

extension MockTripGeneration {
    static func summaryLine(_ summary: SummaryView, withReturn: Bool) -> CopyLine {
        let adaptation = summary.adaptation
        if adaptation.goal == .homeTime {
            return CopyLine(key: "Your plan keeps your clock on your home time.", args: [])
        }
        if adaptation.goal == .routine || adaptation.direction == .none {
            return CopyLine(
                key: "Your trip needs little or no clock shift. Your plan keeps you on your usual routine.", args: [])
        }
        let earlier = adaptation.direction == .earlier
        let days = summary.preparation.emitted
        let key: String
        switch (earlier, days > 0, withReturn) {
        case (true, true, false):
            key =
                "We shift your clock :shift earlier, starting :count day before you leave.|We shift your clock :shift earlier, starting :count days before you leave."
        case (false, true, false):
            key =
                "We shift your clock :shift later, starting :count day before you leave.|We shift your clock :shift later, starting :count days before you leave."
        case (true, true, true):
            key =
                "We shift your clock :shift earlier, starting :count day before you leave. Your trip home is planned too.|We shift your clock :shift earlier, starting :count days before you leave. Your trip home is planned too."
        case (false, true, true):
            key =
                "We shift your clock :shift later, starting :count day before you leave. Your trip home is planned too.|We shift your clock :shift later, starting :count days before you leave. Your trip home is planned too."
        case (true, false, false): key = "We shift your clock :shift earlier during your trip."
        case (false, false, false): key = "We shift your clock :shift later during your trip."
        case (true, false, true):
            key = "We shift your clock :shift earlier during your trip. Your trip home is planned too."
        case (false, false, true):
            key = "We shift your clock :shift later during your trip. Your trip home is planned too."
        }
        var args: [CopyArgument] = [
            .standard(CopyArg(name: "shift", kind: .minutes, value: .number(Decimal(adaptation.shiftMin))))
        ]
        if days > 0 { args.append(.standard(CopyArg(name: "count", kind: .count, value: .number(Decimal(days))))) }
        return CopyLine(key: key, args: args)
    }
}

extension MockTripGeneration {
    static func layovers(_ input: ApiTripInput, legs: [ApiReviewLeg], airports: [ApiAirportSuggestion]) throws
        -> [ApiReviewLayover]
    {
        let inputs = input.outbound.legs + (input.return?.legs ?? [])
        var layovers: [ApiReviewLayover] = []
        for index in 0..<max(0, inputs.count - 1) {
            let leg = inputs[index]
            let next = inputs[index + 1]
            guard leg.toIata == next.fromIata, let airport = airports.first(where: { $0.iata == leg.toIata }) else {
                throw DataFailure.validation(
                    fields: ["review": FieldMessage(key: "Start this flight where the previous flight lands.")],
                    status: 422)
            }
            let arrival = try instant(leg.arriveLocal, airport: airport)
            let departure = try instant(next.departLocal, airport: airport)
            guard departure > arrival else {
                throw DataFailure.validation(
                    fields: ["review": FieldMessage(key: "Check the departure and arrival times.")], status: 422)
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: airport.timezone)!
            var date = calendar.startOfDay(for: arrival)
            var nights = 0
            while date < calendar.startOfDay(for: departure) {
                let nextDate = calendar.date(byAdding: .day, value: 1, to: date)!
                let start = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date)!
                let end = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: nextDate)!
                if arrival <= start && end <= departure { nights += 1 }
                date = nextDate
            }
            let destination = input.return != nil && index == input.outbound.legs.count - 1
            let kind: SegmentKindCode =
                destination ? .destination : nights >= 3 ? .stop : nights >= 1 ? .stopover : .connection
            layovers.append(
                ApiReviewLayover(
                    journey: legs[index].journey, afterLegIndex: legs[index].legIndex, kind: kind,
                    durationMin: Int(departure.timeIntervalSince(arrival) / 60), nights: nights))
        }
        return layovers
    }

    static func stayEnd(_ input: ApiTripInput) throws -> ApiStayEnd? {
        guard ["nights", "check_out"].contains(input.tripEndKind), let leg = input.outbound.legs.last,
            let airport = try airports().first(where: { $0.iata == leg.toIata })
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: airport.timezone)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let leave: Date
        if let declared = leg.stay.checkOutLocal {
            leave = try instant(declared, airport: airport)
        } else if input.tripEndKind == "check_out", let date = input.tripEndCheckOutDate {
            leave = try instant(date + "T12:00", airport: airport)
        } else if let nights = input.tripEndNights {
            let transferEnd =
                try instant(leg.arriveLocal, airport: airport) + Double((45 + (leg.stay.arrivalTransferMin ?? 90)) * 60)
            let hour = calendar.component(.hour, from: transferEnd)
            let firstNight = calendar.date(
                byAdding: .day, value: hour < 3 ? -1 : 0, to: calendar.startOfDay(for: transferEnd))!
            leave = calendar.date(
                byAdding: .day, value: nights,
                to: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: firstNight)!)!
        } else {
            return nil
        }
        return ApiStayEnd(checkOutLocalDate: formatter.string(from: leave), leaveUtc: leave.ISO8601Format())
    }
}

import AppCore
import Foundation

extension WizardForm {
    public func reviewInput(identity: ApiReviewIdentity?, profile: JSONObject? = nil) -> ApiTripReviewInput {
        let inputs = legs.enumerated().map { index, leg in
            let stay = stays.indices.contains(index) ? stays[index] : WizardStay()
            return ApiTripInputLeg(
                fromIata: leg.fromIata, toIata: leg.toIata, departLocal: leg.departLocal, arriveLocal: leg.arriveLocal,
                flightNumber: leg.flightNumber, seatLieFlat: leg.seatLieFlat, seatWindow: leg.seatWindow,
                leaveForAirportLocal: leg.leaveForAirportLocal, airportTransferMin: leg.airportTransferMin,
                stay: ApiTripInputStay(
                    bedAvailableMode: stay.bedAvailableMode, bedAvailableFromLocal: stay.bedAvailableFromLocal,
                    checkOutLocal: stay.checkOutLocal, lateCheckOutOrDayRoom: stay.lateCheckOutOrDayRoom,
                    arrivalTransferMin: stay.arrivalTransferMin, transferMode: stay.transferMode,
                    busyIntervals: stay.busyIntervals.map(\.input)))
        }
        return ApiTripReviewInput(
            input: ApiTripInput(
                outbound: ApiTripInputJourney(legs: Array(inputs.prefix(returnBoundary))),
                return: end.kind == "return_legs"
                    ? ApiTripInputJourney(legs: Array(inputs.dropFirst(returnBoundary))) : nil,
                tripEndKind: end.kind, tripEndNights: end.nights, tripEndCheckOutDate: end.checkOutDate,
                preparationDays: preparation.days, fastDelayOptIn: preparation.fastDelayOptIn,
                override: ApiTripInputOverride(
                    use: override.enabled, habitualBed: override.habitualBed, habitualWake: override.habitualWake,
                    chronotype: override.chronotype),
                latestWake: preparation.latestWake, feasibleNightBed: preparation.feasibleNightBed,
                feasibleNightWake: preparation.feasibleNightWake, preDepartureBusyAnswered: preparation.busyAnswered,
                preDepartureBusyIntervals: preparation.busyIntervals.map(\.input)),
            identity: identity, profile: profile)
    }

    public init(snapshot: ApiTripInputSnapshot, retained: WizardForm? = nil) throws {
        try self.init(input: snapshot.input, airports: snapshot.airports, retained: retained)
    }

    public init(reviewInput: ApiTripReviewInput, retained: WizardForm? = nil) throws {
        try self.init(input: reviewInput.input, retained: retained)
        identity = reviewInput.identity
    }

    public init(input: ApiTripInput, airports: [String: ApiAirportSuggestion] = [:], retained: WizardForm? = nil) throws
    {
        func check(_ value: String?, _ choices: [String]) throws {
            if let value, !choices.contains(value) { throw DataFailure.server(status: nil) }
        }
        try check(input.tripEndKind, ["return_legs", "nights", "check_out", "one_way"])
        try check(input.override.chronotype, ["early", "intermediate", "late"])
        let inputs = input.outbound.legs + (input.return?.legs ?? [])
        legs = try inputs.enumerated().map { index, value in
            try check(value.seatWindow, ["left", "right"])
            var leg = WizardLeg(fromIata: value.fromIata)
            let previous = retained?.legs.indices.contains(index) == true ? retained?.legs[index] : nil
            leg.id = previous?.id ?? "leg-\(index)"
            leg.fromCity = airports[value.fromIata]?.city ?? previous?.fromCity
            leg.toIata = value.toIata
            leg.toCity = airports[value.toIata]?.city ?? previous?.toCity
            leg.departLocal = value.departLocal
            leg.arriveLocal = value.arriveLocal
            leg.flightNumber = value.flightNumber
            leg.seatLieFlat = value.seatLieFlat
            leg.seatWindow = value.seatWindow
            leg.leaveForAirportLocal = value.leaveForAirportLocal
            leg.airportTransferMin = value.airportTransferMin
            return leg
        }
        func busy(_ values: [ApiTripInputBusy], _ retained: [WizardBusy]) -> [WizardBusy] {
            values.enumerated().map { index, value in
                WizardBusy(
                    id: retained.indices.contains(index) ? retained[index].id : "busy-\(index)",
                    startLocal: value.startLocal, endLocal: value.endLocal)
            }
        }
        stays = try inputs.enumerated().map { index, leg in
            let value = leg.stay
            try check(value.bedAvailableMode, ["arrival", "declared"])
            try check(value.transferMode, ["passenger", "self_driven", "unknown"])
            var stay = WizardStay()
            stay.bedAvailableMode = value.bedAvailableMode
            stay.bedAvailableFromLocal = value.bedAvailableFromLocal
            stay.checkOutLocal = value.checkOutLocal
            stay.lateCheckOutOrDayRoom = value.lateCheckOutOrDayRoom
            stay.arrivalTransferMin = value.arrivalTransferMin
            stay.transferMode = value.transferMode
            stay.busyIntervals = busy(
                value.busyIntervals,
                retained?.stays.indices.contains(index) == true ? retained!.stays[index].busyIntervals : [])
            return stay
        }
        end.kind = input.tripEndKind
        end.nights = input.tripEndNights
        end.checkOutDate = input.tripEndCheckOutDate
        end.returnFromLeg = input.tripEndKind == "return_legs" ? input.outbound.legs.count : nil
        override.enabled = input.override.use
        override.habitualBed = input.override.habitualBed
        override.habitualWake = input.override.habitualWake
        override.chronotype = input.override.chronotype
        preparation.days = input.preparationDays
        preparation.latestWake = input.latestWake
        preparation.busyAnswered = input.preDepartureBusyAnswered
        preparation.busyIntervals = busy(input.preDepartureBusyIntervals, retained?.preparation.busyIntervals ?? [])
        preparation.feasibleNightBed = input.feasibleNightBed
        preparation.feasibleNightWake = input.feasibleNightWake
        preparation.fastDelayOptIn = input.fastDelayOptIn
        identity = retained?.identity
        itinerary = retained?.itinerary
    }
}

public enum WizardJourney {
    public static func errorStep(_ errors: [String: FieldMessage], form: WizardForm) -> MemberWizardStep {
        for index in form.legs.indices {
            let home = index >= form.returnBoundary
            if errors.keys.contains(where: { $0 == "legs.\(index).fromIata" || $0 == "legs.\(index).toIata" }) {
                return home ? .returnRoute : .whereTo
            }
        }
        let outbound = errors.keys.contains { key in
            (0..<form.returnBoundary).contains { key.hasPrefix("legs.\($0).") }
        }
        return form.end.kind == "return_legs" && !outbound ? .returnFlight : .outbound
    }

    static var topFields: [String: String] {
        [
            "trip_end_kind": "end.kind", "trip_end_nights": "end.nights", "trip_end_check_out_date": "end.checkOutDate",
            "return_from_leg": "end.returnFromLeg", "preparation_days": "preparation.days",
            "latest_wake": "preparation.latestWake",
            "pre_departure_busy_answered": "preparation.busyAnswered",
            "pre_departure_busy_intervals": "preparation.busyIntervals",
            "feasible_night_bed": "preparation.feasibleNightBed",
            "feasible_night_wake": "preparation.feasibleNightWake",
            "fast_delay_opt_in": "preparation.fastDelayOptIn", "use_profile_override": "override.enabled",
            "override_habitual_bed": "override.habitualBed", "override_habitual_wake": "override.habitualWake",
            "override_chronotype": "override.chronotype",
        ]
    }

    static func camel(_ value: String) -> String {
        let words = value.split(separator: "_", omittingEmptySubsequences: false)
        return (words.first.map(String.init) ?? "")
            + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    public static func errorPath(_ path: String, form: WizardForm) -> String {
        let parts = path.split(separator: ".").map(String.init)
        if parts.count >= 3, ["outbound", "return"].contains(parts[0]), parts[1] == "legs", let position = Int(parts[2])
        {
            let index = position + (parts[0] == "return" ? form.returnBoundary : 0)
            let stay = parts.count > 3 && parts[3] == "stay"
            return ([stay ? "stays" : "legs", String(index)] + parts.dropFirst(stay ? 4 : 3).map(camel)).joined(
                separator: ".")
        }
        if path == "override.use" { return "override.enabled" }
        guard let first = parts.first else { return path }
        return ([topFields[first] ?? first] + parts.dropFirst().map(camel)).joined(separator: ".")
    }

    public static func errors(_ fields: [String: FieldMessage], form: WizardForm) -> [String: FieldMessage] {
        Dictionary(
            fields.map { path, message in
                (
                    message.key == "Your flight home must leave from the airport you landed at."
                        ? "review" : errorPath(path, form: form), message
                )
            }, uniquingKeysWith: { _, last in last })
    }
}

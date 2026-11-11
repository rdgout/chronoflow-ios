import AppCore
import Foundation

public enum WizardOutboundRules {
    public static func errors(form: WizardForm, airports: [String: ApiAirportSuggestion], now: Date, checkPast: Bool)
        -> [String: FieldMessage]
    {
        var errors = WizardValidation.validate(form).filter { entry in
            (0..<form.returnBoundary).contains { entry.key.hasPrefix("legs.\($0).") }
        }
        for (index, leg) in form.legs.prefix(form.returnBoundary).enumerated() {
            if let from = airports[leg.fromIata], let to = airports[leg.toIata],
                let departure = WizardDateTime.instant(leg.departLocal, zone: from.timezone),
                let arrival = WizardDateTime.instant(leg.arriveLocal, zone: to.timezone), arrival <= departure
            {
                errors["legs.\(index).arriveLocal"] = FieldMessage(key: "Check the departure and arrival times.")
            }
        }
        if checkPast, form.end.kind != "return_legs", errors.isEmpty,
            let last = form.legs.prefix(form.returnBoundary).last,
            let airport = airports[last.toIata],
            let arrival = WizardDateTime.instant(last.arriveLocal, zone: airport.timezone), arrival <= now
        {
            errors["review"] = FieldMessage(
                key: "A new plan needs an upcoming arrival. Check your flight dates or add your return flight.")
        }
        return errors
    }

    public static func connection(
        form: WizardForm, index: Int, airports: [String: ApiAirportSuggestion] = [:], duration: (Int) -> String
    ) -> FieldMessage? {
        guard index > 0, form.legs.indices.contains(index), index != form.returnBoundary else { return nil }
        let leg = form.legs[index - 1]
        let airport = leg.toCity ?? leg.toIata
        guard !airport.isEmpty else { return nil }
        let home = index >= form.returnBoundary
        let localIndex = index - 1 - (home ? form.returnBoundary : 0)
        if let fact = form.itinerary?.layovers.first(where: {
            $0.journey == (home ? .return : .outbound) && $0.afterLegIndex == localIndex
        }) {
            return connectionMessage(
                airport: airport, minutes: fact.durationMin, nights: fact.kind == .connection ? 0 : fact.nights,
                duration: duration)
        }
        if let zone = airports[leg.toIata]?.timezone,
            let arrival = WizardDateTime.instant(leg.arriveLocal, zone: zone),
            let departure = WizardDateTime.instant(form.legs[index].departLocal, zone: zone), departure > arrival
        {
            return connectionMessage(
                airport: airport, minutes: Int(departure.timeIntervalSince(arrival) / 60),
                nights: completeNights(arrival: leg.arriveLocal, departure: form.legs[index].departLocal, zone: zone),
                duration: duration)
        }
        return FieldMessage(key: "Stop in {{airport}}", arguments: ["airport": .string(airport)])
    }

    public static func flightMinutes(form: WizardForm, index: Int, airports: [String: ApiAirportSuggestion]) -> Int? {
        guard form.legs.indices.contains(index) else { return nil }
        let leg = form.legs[index]
        if let from = airports[leg.fromIata], let to = airports[leg.toIata],
            let departure = WizardDateTime.instant(leg.departLocal, zone: from.timezone),
            let arrival = WizardDateTime.instant(leg.arriveLocal, zone: to.timezone), arrival > departure
        {
            return Int(arrival.timeIntervalSince(departure) / 60)
        }
        return nil
    }

    private static func completeNights(arrival: String, departure: String, zone: String) -> Int {
        guard let start = WizardDateTime.date(arrival), let end = WizardDateTime.date(departure),
            let landing = WizardDateTime.instant(arrival, zone: zone),
            let takeoff = WizardDateTime.instant(departure, zone: zone)
        else { return 0 }
        var day = WizardDateTime.calendar.startOfDay(for: start)
        var count = 0
        // Match the planner's complete local 23:00–07:00 windows, including DST nights.
        while day < end {
            let next = WizardDateTime.calendar.date(byAdding: .day, value: 1, to: day)!
            let date = String(WizardDateTime.string(day).prefix(10))
            let nextDate = String(WizardDateTime.string(next).prefix(10))
            if let bed = WizardDateTime.instant(date + "T23:00", zone: zone),
                let wake = WizardDateTime.instant(nextDate + "T07:00", zone: zone), bed >= landing, wake <= takeoff
            {
                count += 1
            }
            day = next
        }
        return count
    }

    private static func connectionMessage(airport: String, minutes: Int, nights: Int, duration: (Int) -> String)
        -> FieldMessage
    {
        if nights > 0 {
            return FieldMessage(
                key: nights == 1
                    ? "Stop in {{airport}} · {{count}} complete night"
                    : "Stop in {{airport}} · {{count}} complete nights",
                arguments: ["airport": .string(airport), "count": .number(Decimal(nights))])
        }
        return FieldMessage(
            key: "Connection in {{airport}} · {{duration}}",
            arguments: [
                "airport": .string(airport),
                "duration": .string(duration(minutes)),
            ])
    }
}

public enum WizardFlightRules {
    public static func errors(form: WizardForm, airports: [String: ApiAirportSuggestion], now: Date, checkPast: Bool)
        -> [String: FieldMessage]
    {
        var errors = WizardValidation.validate(form).filter { $0.key.hasPrefix("legs.") }
        for (index, leg) in form.legs.enumerated() {
            if let from = airports[leg.fromIata], let to = airports[leg.toIata],
                let departure = WizardDateTime.instant(leg.departLocal, zone: from.timezone),
                let arrival = WizardDateTime.instant(leg.arriveLocal, zone: to.timezone), arrival <= departure
            {
                errors["legs.\(index).arriveLocal"] = FieldMessage(key: "Check the departure and arrival times.")
            }
        }
        if checkPast, errors.isEmpty, let last = form.legs.last, let airport = airports[last.toIata],
            let arrival = WizardDateTime.instant(last.arriveLocal, zone: airport.timezone), arrival <= now
        {
            errors["review"] = FieldMessage(
                key: form.end.kind == "return_legs"
                    ? "A new plan needs an upcoming arrival. Check your flight dates."
                    : "A new plan needs an upcoming arrival. Check your flight dates or add your return flight.")
        }
        return errors
    }
}

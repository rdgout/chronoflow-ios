import AppCore
import Foundation

public enum WizardOutboundRules {
    public static func errors(form: WizardForm, airports: [String: ApiAirportSuggestion], now: Date, checkPast: Bool)
        -> [String: FieldMessage]
    {
        var errors = WizardValidation.validate(form).filter { $0.key.hasPrefix("legs.") }
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

    public static func connection(form: WizardForm, index: Int, duration: (Int) -> String) -> FieldMessage? {
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
        return FieldMessage(key: "Stop in {{airport}}", arguments: ["airport": .string(airport)])
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

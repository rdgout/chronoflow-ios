import AppCore
import Foundation

public enum WizardValidation {
    public static func validate(_ form: WizardForm, airports: [String: ApiAirportSuggestion] = [:]) -> [String:
        FieldMessage]
    {
        var errors: [String: FieldMessage] = [:]
        let timing = WizardFlightTiming(form: form, airports: airports)
        func error(_ path: String, _ key: String = "The planner cannot use this value.") {
            errors[path] = FieldMessage(key: key)
        }
        func dateTime(_ path: String, _ value: String?, required: Bool = false) {
            if (value ?? "").isEmpty {
                if required { error(path, "Please fill this in.") }
            } else if WizardDateTime.date(value!) == nil {
                error(path, "Enter a valid date and time.")
            }
        }
        func minutes(_ path: String, _ value: Int?) { if let value, !(0...65535).contains(value) { error(path) } }
        func busy(_ path: String, _ rows: [WizardBusy]) {
            if rows.count > 32 { error(path) }
            for (index, row) in rows.enumerated() {
                dateTime("\(path).\(index).startLocal", row.startLocal, required: true)
                dateTime("\(path).\(index).endLocal", row.endLocal, required: true)
                if WizardDateTime.date(row.startLocal) != nil, WizardDateTime.date(row.endLocal) != nil,
                    row.endLocal <= row.startLocal
                {
                    error("\(path).\(index).endLocal", "Busy time must end after it starts.")
                }
            }
        }
        if form.legs.isEmpty || form.legs.count > WizardForm.maxFlights || form.stays.count != form.legs.count {
            error("legs")
        }
        for (index, leg) in form.legs.enumerated() {
            let path = "legs.\(index)"
            if leg.fromIata.isEmpty { error(path + ".fromIata", "Choose the airport you leave from.") }
            if leg.toIata.isEmpty { error(path + ".toIata", "Choose the airport you land at.") }
            if !leg.fromIata.isEmpty, leg.fromIata == leg.toIata {
                error(path + ".toIata", "Choose different departure and arrival airports.")
            }
            dateTime(path + ".departLocal", leg.departLocal, required: true)
            dateTime(path + ".arriveLocal", leg.arriveLocal, required: true)
            dateTime(path + ".leaveForAirportLocal", leg.leaveForAirportLocal)
            if let leave = leg.leaveForAirportLocal, WizardDateTime.date(leave) != nil,
                WizardDateTime.date(leg.departLocal) != nil,
                leave >= leg.departLocal
            {
                error(path + ".leaveForAirportLocal", "Check the departure and arrival times.")
            }
            minutes(path + ".airportTransferMin", leg.airportTransferMin)
            if (leg.flightNumber?.count ?? 0) > 12 { error(path + ".flightNumber") }
            if index > 0 {
                let previous = form.legs[index - 1]
                if !previous.toIata.isEmpty, !leg.fromIata.isEmpty, previous.toIata != leg.fromIata {
                    error(path + ".fromIata", "Start this flight where the previous flight lands.")
                }
                if let arrival = timing.instant(for: .arrival(index - 1)),
                    let departure = timing.instant(for: .departure(index)), departure <= arrival
                {
                    error(path + ".departLocal", "This flight leaves before the previous one lands.")
                }
            }
        }
        for (index, stay) in form.stays.enumerated() {
            let path = "stays.\(index)"
            dateTime(
                path + ".bedAvailableFromLocal", stay.bedAvailableFromLocal,
                required: stay.bedAvailableMode == "declared")
            dateTime(path + ".checkOutLocal", stay.checkOutLocal)
            minutes(path + ".arrivalTransferMin", stay.arrivalTransferMin)
            busy(path + ".busyIntervals", stay.busyIntervals)
        }
        if form.end.kind == "nights", !(1...60).contains(form.end.nights ?? 0) { error("end.nights") }
        if form.end.kind == "check_out", WizardDateTime.date((form.end.checkOutDate ?? "") + "T12:00") == nil {
            error("end.checkOutDate", "Enter a valid date and time.")
        }
        if form.end.kind == "return_legs",
            (form.end.returnFromLeg ?? 0) < 1 || (form.end.returnFromLeg ?? 0) >= form.legs.count
        {
            error("end.returnFromLeg")
        }
        let sleepError = "Check your bedtime and wake-up time."
        if form.override.enabled {
            if !WizardDateTime.isTime(form.override.habitualBed) { error("override.habitualBed", sleepError) }
            if !WizardDateTime.isTime(form.override.habitualWake) { error("override.habitualWake", sleepError) }
        }
        let prep = form.preparation
        if !(0...WizardForm.maxPreparationDays).contains(prep.days) { error("preparation.days") }
        for (field, value) in [
            ("latestWake", prep.latestWake), ("feasibleNightBed", prep.feasibleNightBed),
            ("feasibleNightWake", prep.feasibleNightWake),
        ] {
            if value != nil, !WizardDateTime.isTime(value) { error("preparation." + field, sleepError) }
        }
        if (prep.feasibleNightBed == nil) != (prep.feasibleNightWake == nil) {
            error("preparation.feasibleNightBed", sleepError)
        }
        busy("preparation.busyIntervals", prep.busyIntervals)
        return errors
    }

    public static func validationErrors(_ fields: [String: FieldMessage], form: WizardForm) -> [String: FieldMessage] {
        WizardJourney.errors(fields, form: form).filter { path, _ in
            ["legs", "stays", "end", "override", "preparation"].contains { path == $0 || path.hasPrefix($0 + ".") }
        }
    }

    public static func errorSection(_ path: String, form: WizardForm) -> FieldMessage {
        let parts = WizardJourney.errorPath(path, form: form).split(separator: ".").map(String.init)
        let section = parts.first ?? ""
        if section == "preparation" { return FieldMessage(key: "Preparation") }
        if section == "override" { return FieldMessage(key: "Your sleep for this trip") }
        let position = parts.count > 1 ? parts[1] : ""
        let field = parts.count > 2 ? parts[2] : ""
        if section == "end" {
            if position == "nights" { return FieldMessage(key: "Nights at your destination") }
            if position == "checkOutDate" { return FieldMessage(key: "End of stay") }
        }
        if ["legs", "stays"].contains(section), let index = Int(position), form.legs.indices.contains(index) {
            if section == "legs", index == 0, field.hasPrefix("leaveForAirport") || field == "airportTransferMin" {
                return FieldMessage(key: "Leaving for the airport")
            }
            if section == "stays" {
                if field == "busyIntervals" { return FieldMessage(key: "Nights at your destination") }
                if index == form.returnBoundary - 1 {
                    return FieldMessage(
                        key: ["checkOutLocal", "lateCheckOutOrDayRoom"].contains(field) ? "End of stay" : "Arrival")
                }
            }
            return FieldMessage(
                key: index < form.returnBoundary ? "Outbound, flight {{number}}" : "Return, flight {{number}}",
                arguments: ["number": .number(Decimal(index + 1))])
        }
        return FieldMessage(key: "Your flights")
    }
}

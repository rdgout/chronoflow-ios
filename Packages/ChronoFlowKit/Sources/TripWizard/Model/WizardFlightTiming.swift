import AppCore
import Foundation

public struct WizardFlightTiming: Sendable {
    public enum Field: Sendable {
        case departure(Int)
        case arrival(Int)

        var index: Int {
            switch self {
            case .departure(let index), .arrival(let index): index
            }
        }

        var position: Int {
            index * 2 + (isArrival ? 1 : 0)
        }

        var isArrival: Bool {
            if case .arrival = self { true } else { false }
        }

        init(position: Int) {
            self = position.isMultiple(of: 2) ? .departure(position / 2) : .arrival(position / 2)
        }
    }

    let form: WizardForm
    let airports: [String: ApiAirportSuggestion]

    public init(form: WizardForm, airports: [String: ApiAirportSuggestion]) {
        self.form = form
        self.airports = airports
    }

    public func minimumLocal(for field: Field) -> Date? {
        guard form.legs.indices.contains(field.index), field.position > 0,
            let previous = instant(for: Field(position: field.position - 1)), let zone = zone(for: field)
        else { return nil }
        return WizardDateTime.localDate(previous, zone: zone)
    }

    public func initialLocal(for field: Field, now: Date) -> Date {
        if let stored = value(for: field).flatMap(WizardDateTime.date) { return stored }
        if form.legs.indices.contains(field.index), let zone = zone(for: field) {
            for position in (0..<field.position).reversed() {
                if let previous = instant(for: Field(position: position)),
                    let local = WizardDateTime.localDate(previous, zone: zone)
                {
                    return local
                }
            }
        }
        let localNow = zone(for: field).flatMap { WizardDateTime.localDate(now, zone: $0) } ?? now
        return max(localNow, minimumLocal(for: field) ?? localNow)
    }

    func instant(for field: Field) -> Date? {
        guard let value = value(for: field), let zone = zone(for: field) else { return nil }
        return WizardDateTime.instant(value, zone: zone)
    }

    private func value(for field: Field) -> String? {
        guard form.legs.indices.contains(field.index) else { return nil }
        let leg = form.legs[field.index]
        return field.isArrival ? leg.arriveLocal : leg.departLocal
    }

    private func zone(for field: Field) -> String? {
        guard form.legs.indices.contains(field.index) else { return nil }
        let leg = form.legs[field.index]
        return airports[field.isArrival ? leg.toIata : leg.fromIata]?.timezone
    }
}

extension MemberWizardModel {
    public func minimumLocal(for field: WizardFlightTiming.Field) -> Date? {
        WizardFlightTiming(form: draft.form, airports: draft.airports).minimumLocal(for: field)
    }

    public func initialLocal(for field: WizardFlightTiming.Field) -> Date {
        WizardFlightTiming(form: draft.form, airports: draft.airports).initialLocal(for: field, now: now())
    }
}

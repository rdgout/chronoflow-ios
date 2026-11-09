import AppCore
import Foundation

public struct CopyFormat: Sendable {
    public var language: Language
    public var timeFormat: TimeFormat
    public var displayZone: String?
    public var annotateInstantZone: Bool
    public var trip: TripDetailView?

    public init(
        language: Language, timeFormat: TimeFormat = .value24, displayZone: String? = nil,
        annotateInstantZone: Bool = false, trip: TripDetailView? = nil
    ) {
        self.language = language
        self.timeFormat = timeFormat
        self.displayZone = displayZone
        self.annotateInstantZone = annotateInstantZone
        self.trip = trip
    }
}

public struct CopyLineFormatter: Sendable {
    public let catalog: CopyCatalog
    public init(catalog: CopyCatalog) { self.catalog = catalog }

    public func format(_ line: CopyLine, options: CopyFormat) -> String {
        var arguments: [String: String] = [:]
        var count = 1.0
        for arg in line.args {
            switch arg {
            case .standard(let arg):
                arguments[arg.name] = formatArgument(arg, options: options)
                if arg.kind == .count && arg.name == "count" { count = arg.value.number }
            case .caffeine(let arg):
                arguments[arg.name] =
                    arg.usualDrinks.map { usualDrinks($0, language: options.language) }
                    ?? caffeineAmount(CaffeineAmountView(mg: arg.value, drinks: arg.drinks), language: options.language)
            }
        }
        return catalog.text(line.key, language: options.language, arguments: arguments, count: count)
    }

    public func formatArgument(_ arg: CopyArg, options: CopyFormat) -> String {
        let value = arg.value.text
        let number = arg.value.number
        switch arg.kind {
        case .date: return formatDate(value, language: options.language)
        case .instant:
            let zone = arg.tz ?? options.displayZone ?? "UTC"
            let time = formatInstant(value, options: options, zone: zone)
            return options.annotateInstantZone && zone != options.displayZone
                ? "\(time) (\(zoneLabel(zone, trip: options.trip)))" : time
        case .offset: return formatOffset(number, language: options.language)
        case .minutes: return formatMinutes(number, language: options.language)
        case .count: return formatNumber(number, language: options.language)
        case .milligrams:
            return text(":amount mg", options.language, ["amount": formatNumber(number, language: options.language)])
        case .place, .text, .unknown: return value
        }
    }

    public func formatNumber(_ value: Double, language: Language) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language == .nl ? "nl_NL" : "en_GB")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value))!
    }

    public func formatDate(_ value: String, language: Language, zone: String = "UTC") -> String {
        dateText(value, language: language, zone: zone, template: "d MMM yyyy")
    }

    public func formatDayMonth(_ value: String, language: Language, zone: String = "UTC") -> String {
        dateText(value, language: language, zone: zone, template: "d MMM")
    }

    public func formatWeekdayDate(_ value: String, language: Language, zone: String = "UTC", month: Bool = true)
        -> String
    {
        dateText(value, language: language, zone: zone, template: month ? "EEE d MMM" : "EEE d")
    }

    public func formatMonthYear(_ value: String, language: Language, zone: String = "UTC") -> String {
        dateText(value, language: language, zone: zone, template: "MMM yyyy")
    }

    private func dateText(_ value: String, language: Language, zone: String, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .nl ? "nl_NL" : "en_GB")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = template
        return formatter.string(from: planDate(value)).replacingOccurrences(of: ".", with: "")
    }

    public func formatInstant(_ value: String, options: CopyFormat, zone: String? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone ?? options.displayZone ?? "UTC") ?? .gmt
        let parts = calendar.dateComponents([.hour, .minute], from: planDate(value))
        let hour = parts.hour!
        let minute = parts.minute!
        if options.timeFormat != .value12 { return String(format: "%02d:%02d", hour, minute) }
        return String(format: "%02d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute) + " "
            + text(hour < 12 ? "AM" : "PM", options.language)
    }

    public func formatMinutes(_ value: Double, language: Language, duration: Bool = false) -> String {
        let hours = floor(value / 60)
        let minutes = value.truncatingRemainder(dividingBy: 60)
        if !duration { return text(":amount min", language, ["amount": formatNumber(value, language: language)]) }
        if hours > 0 && minutes > 0 {
            return text(
                ":hours hr :minutes min", language,
                [
                    "hours": formatNumber(hours, language: language),
                    "minutes": formatNumber(minutes, language: language),
                ])
        }
        return text(
            hours > 0 ? ":amount hr" : ":amount min", language,
            ["amount": formatNumber(hours > 0 ? hours : minutes, language: language)])
    }

    public func formatOffset(_ value: Double, language: Language) -> String {
        let absolute = abs(value)
        let hours = floor(absolute / 60)
        let minutes = absolute.truncatingRemainder(dividingBy: 60)
        let duration =
            minutes != 0
            ? text(
                ":hours h :minutes min", language,
                [
                    "hours": formatNumber(hours, language: language),
                    "minutes": formatNumber(minutes, language: language),
                ]) : text(":amount h", language, ["amount": formatNumber(hours, language: language)])
        return (value > 0 ? "+" : value < 0 ? "−" : "") + duration
    }

    public func drink(_ amount: DrinkAmountView, language: Language, chip: Bool = false) -> String {
        let key: String
        switch amount.drink {
        case .filterCoffee, .espresso:
            key = chip ? ":amount coffee|:amount coffees" : "half a cup of coffee|:amount cups of coffee"
        case .tea: key = chip ? ":amount tea|:amount teas" : "half a cup of tea|:amount cups of tea"
        case .cola:
            key =
                chip ? ":amount soft drink|:amount soft drinks" : "half a can of soft drink|:amount cans of soft drink"
        case .energyDrink:
            key =
                chip
                ? ":amount energy drink|:amount energy drinks"
                : "half a can of energy drink|:amount cans of energy drink"
        case .unknown: return ""
        }
        let whole = amount.halves >= 2 ? formatNumber(Double(amount.halves / 2), language: language) : ""
        let quantity = whole + (amount.halves % 2 == 1 ? "½" : "")
        return catalog.text(key, language: language, arguments: ["amount": quantity], count: Double(amount.halves))
    }

    public func usualDrinks(_ count: Int, language: Language) -> String {
        catalog.text(
            ":count drink|:count drinks", language: language,
            arguments: ["count": formatNumber(Double(count), language: language)], count: Double(count))
    }

    public func caffeineAmount(_ amount: CaffeineAmountView, language: Language) -> String {
        let mg = text(":n mg", language, ["n": formatNumber(Double(amount.mg), language: language)])
        let drinks = amount.drinks.map { drink($0, language: language) }
        guard let first = drinks.first else { return mg }
        let description =
            drinks.count == 2 ? text(":first or :second", language, ["first": first, "second": drinks[1]]) : first
        return text(":drinks (:mg)", language, ["drinks": description, "mg": mg])
    }

    func text(_ key: String, _ language: Language, _ arguments: [String: String] = [:]) -> String {
        catalog.text(key, language: language, arguments: arguments)
    }
}

extension CopyArgValue {
    var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): NSDecimalNumber(decimal: value).stringValue
        }
    }
    var number: Double { Double(text) ?? 0 }
}

public func planDate(_ value: String) -> Date {
    var value = value.count == 10 ? value + "T12:00:00Z" : value
    if value.count == 17 && value.hasSuffix("Z") { value = String(value.dropLast()) + ":00Z" }
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
    return (try? Date.ISO8601FormatStyle().parse(value)) ?? Date(timeIntervalSince1970: .nan)
}

public func zoneLabel(_ zone: String, trip: TripDetailView? = nil) -> String {
    let airports = trip.map { [$0.from, $0.to] + $0.legs.flatMap { [$0.from, $0.to] } } ?? []
    return airports.first { $0.zone == zone && $0.city != nil }?.city
        ?? String(zone.split(separator: "/").last ?? Substring(zone)).replacingOccurrences(of: "_", with: " ")
}

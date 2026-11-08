import AppCore
import Foundation

extension CopyLineFormatter {
    public func dayDateLabel(_ day: DayView, language: Language) -> String {
        guard let range = day.labelRange, range != day.labelDate else {
            return formatWeekdayDate(day.labelDate, language: language)
        }
        let first = formatWeekdayDate(
            day.labelDate, language: language, month: day.labelDate.prefix(7) != range.prefix(7))
        return first + " – " + formatWeekdayDate(range, language: language)
    }

    public func nowLabel(_ layout: DayLayout, now: Date, options: CopyFormat) -> String {
        let zone =
            layout.day.zones.first { planDate($0.startUtc) <= now && now < planDate($0.endUtc) }?.tz
            ?? layout.day.zones.last?.tz
        return formatInstant(now.ISO8601Format(), options: options, zone: zone)
    }

    public func blockInterval(_ block: BlockView, options: CopyFormat, separator: String = " – ") -> String {
        let zone = block.displayTz
        let dates = localDate(block.startUtc, zone: zone) != localDate(block.endUtc, zone: zone)
        let offsets = utcOffset(block.startUtc, zone: zone) != utcOffset(block.endUtc, zone: zone)
        func endpoint(_ at: String) -> String {
            (dates ? formatDate(at, language: options.language, zone: zone) + " " : "")
                + formatInstant(at, options: options, zone: zone) + (offsets ? " (\(utcOffset(at, zone: zone)))" : "")
        }
        return endpoint(block.startUtc) + separator + endpoint(block.endUtc)
    }
}

public func localDate(_ at: String, zone: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: planDate(at))
}

public func utcOffset(_ at: String, zone: String) -> String {
    let offset = (TimeZone(identifier: zone) ?? .gmt).secondsFromGMT(for: planDate(at))
    guard offset != 0 else { return "GMT" }
    return String(format: "GMT%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) / 60 % 60)
}

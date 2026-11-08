import Foundation

public enum WizardDateTime {
    // Picker dates carry airport wall components; the phone's time zone must never normalize them.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    public static func isTime(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    public static func date(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let parts = value.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard parts.count == 5, parts[0] > 0,
            let date = calendar.date(
                from: DateComponents(
                    year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])),
            string(date) == value
        else { return nil }
        return date
    }

    public static func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d", parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!)
    }

    public static func shiftDate(_ value: String, days: Int) -> String? {
        guard let date = date(String(value.prefix(10)) + "T12:00"),
            let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return String(string(shifted).prefix(10))
    }

    public static func pickerValue(_ value: String?, fallbackDate: String, dateTime: Bool = true) -> String {
        if dateTime { return value.flatMap { date($0) == nil ? nil : $0 } ?? fallbackDate + "T12:00" }
        return isTime(value) ? value! : "12:00"
    }

    public static func pickerDate(_ value: String, dateTime: Bool = true) -> Date? {
        date(dateTime ? value : "2001-01-15T" + value)
    }

    public static func pickedValue(_ date: Date, dateTime: Bool = true) -> String {
        let value = string(date)
        return dateTime ? value : String(value.suffix(5))
    }

    public static func instant(_ value: String, zone: String) -> Date? {
        guard let wall = date(value), let timeZone = TimeZone(identifier: zone) else { return nil }
        var local = calendar
        local.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: wall)
        guard let instant = local.date(from: parts),
            local.dateComponents([.year, .month, .day, .hour, .minute], from: instant) == parts
        else { return nil }
        return instant
    }

    public static func formatLocal(_ value: String?, locale: Locale) -> String? {
        guard let value, let date = date(value) else { return value }
        return format(date, template: "EEE d MMM", locale: locale) + " · " + value.suffix(5)
    }

    public static func formatWeekdayTime(_ value: String?, locale: Locale, twelveHour: Bool = false) -> String? {
        guard let value, let date = date(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let dutch = locale.language.languageCode?.identifier == "nl"
        formatter.dateFormat = twelveHour ? (dutch ? "EEE hh:mm a" : "EEE h:mm a") : "EEE HH:mm"
        formatter.amSymbol = dutch ? "a.m." : "AM"
        formatter.pmSymbol = dutch ? "p.m." : "PM"
        return formatter.string(from: date)
    }

    public static func format(_ date: Date, template: String, locale: Locale, zone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = zone ?? calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    public static func parseInstant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: value) { return date }
        if value.count == 17, value.hasSuffix("Z") {
            return ISO8601DateFormatter().date(from: value.dropLast() + ":00Z")
        }
        return nil
    }
}

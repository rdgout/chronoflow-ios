import AppCore
import Foundation

public enum SettingsPasskeyText {
    public static func count(_ count: Int, language: Language) -> String {
        SettingsStrings.text("%lld passkeys", language: language, count: count)
    }

    public static func meta(
        _ passkey: ApiPasskey, language: Language, locale: Locale, now: Date, calendar: Calendar = .current
    ) -> String? {
        let added = date(passkey.createdAt)
        let used = date(passkey.lastUsedAt)
        var parts: [String] = []
        if let added {
            parts.append(
                SettingsStrings.text(
                    "Added {{date}}", language: language,
                    ["date": added.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))]))
        }
        if let used {
            let text =
                calendar.isDate(used, inSameDayAs: now)
                ? SettingsStrings.text("today", language: language)
                : used.formatted(
                    calendar.isDate(used, equalTo: now, toGranularity: .year)
                        ? .dateTime.day().month(.abbreviated).locale(locale)
                        : .dateTime.day().month(.abbreviated).year().locale(locale))
            parts.append(SettingsStrings.text("used {{date}}", language: language, ["date": text]))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
            ?? (try? Date.ISO8601FormatStyle().parse(raw))
    }
}

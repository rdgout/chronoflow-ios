import AppCore
import Foundation

enum MockSettings {
    static func camel(_ key: String) -> String {
        let components = key.split(separator: "_")
        return String(components[0])
            + components.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
    static func invalid(_ field: String, _ key: String = "Choose one of the available options.") -> DataFailure {
        .validation(fields: [field: FieldMessage(key: key)], status: 422)
    }
    static func validate(section: SettingsSection, patch: JSONObject, current: AccountSettings) throws {
        try SettingsPatchValidation.validate(section: section, patch: patch)
        var fields: [String: FieldMessage] = [:]
        for key in patch.fields.keys.sorted() {
            let value = patch.fields[key]!
            let valid: Bool
            switch section {
            case .preferences:
                switch key {
                case "time_format": valid = value == .string("12") || value == .string("24")
                case "show_optional_items": if case .bool = value { valid = true } else { valid = false }
                default:
                    if case .array(let list) = value {
                        let types = list.compactMap { value -> BlockType? in
                            guard let raw = value.string else { return nil }
                            let type = BlockType(rawValue: raw)
                            if case .unknown = type { return nil }
                            return type
                        }
                        valid = types.count == list.count && Set(types).count == list.count
                    } else {
                        valid = false
                    }
                }
            case .reminders:
                if key == "lead_min" {
                    valid = [JSONValue.number(15), .number(30), .number(60)].contains(value)
                } else {
                    if case .bool = value { valid = true } else { valid = false }
                }
            case .bodyClock: valid = bodyValue(key: key, value: value)
            }
            if !valid {
                fields[key] = FieldMessage(
                    key: key.contains("bed") || key.contains("wake")
                        ? "Enter a valid time." : "Choose one of the available options.")
            }
        }
        if !fields.isEmpty { throw DataFailure.validation(fields: fields, status: 422) }
        if section == .bodyClock {
            var merged = current.bodyClock
            for (key, value) in patch.fields { merged[camel(key)] = value }
            for (bed, wake, field) in [
                ("habitualBed", "habitualWake", "habitual_bed"), ("freeDayBed", "freeDayWake", "free_day_bed"),
            ] {
                if bed == "freeDayBed" && merged["freeDayStatus"] != .string("declared") { continue }
                if let bedTime = merged[bed]?.string, let wakeTime = merged[wake]?.string {
                    let minutes: (String) -> Int? = { time in
                        let parts = time.split(separator: ":").compactMap { Int($0) }
                        guard parts.count == 2 else { return nil }
                        return parts[0] * 60 + parts[1]
                    }
                    guard let wakeMinutes = minutes(wakeTime), let bedMinutes = minutes(bedTime) else {
                        throw invalid(field, "Check your bedtime and wake-up time.")
                    }
                    let duration = (wakeMinutes - bedMinutes + 1440) % 1440
                    if !(180...840).contains(duration) { throw invalid(field, "Check your bedtime and wake-up time.") }
                }
            }
            if merged["freeDayStatus"] == .string("declared")
                && (merged["freeDayBed"]?.string == nil || merged["freeDayWake"]?.string == nil)
            {
                throw invalid("free_day_bed", "Check your bedtime and wake-up time.")
            }
            if merged["caffeineHabit"] != .string("cups") {
                for key in ["cups_filter_coffee", "cups_tea", "cups_cola", "cups_energy_drink"] {
                    if case .number(let count) = patch[key], count > 0 {
                        throw invalid(key, "Add your usual drinks per day, or leave your caffeine habits unanswered.")
                    }
                }
            }
            if merged["caffeineHabit"] == .string("cups") {
                let counts = ["cupsFilterCoffee", "cupsTea", "cupsCola", "cupsEnergyDrink"].compactMap {
                    key -> Decimal? in
                    if case .number(let number) = merged[key] { number } else { nil }
                }
                if counts.reduce(0, +) == 0 {
                    throw invalid("cups_filter_coffee", "Add at least one drink to save this answer.")
                }
            }
            if merged["blueBlockers"] == .string("rated") && merged["blueBlockerMdfd"] == .null {
                throw invalid("blue_blocker_mdfd", "Enter a rating between 0.1 and 9.9.")
            }
        }
    }
    private static func bodyValue(key: String, value: JSONValue) -> Bool {
        if ["habitual_bed", "habitual_wake", "free_day_bed", "free_day_wake"].contains(key) {
            if value == .null { return key.hasPrefix("free_day_") }
            guard let time = value.string else { return false }
            return time.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil
        }
        let choices = [
            "free_day_status": ["unconfirmed", "same_as_workdays", "declared"],
            "chronotype": ["early", "intermediate", "late"], "age_band": ["under_18", "18_64", "65_plus"],
            "caffeine_habit": ["non_user", "cups"], "light_device": ["none", "box", "glasses"],
            "blue_blockers": ["no", "rated", "unrated"],
        ]
        if let options = choices[key] {
            return value == .null && key != "free_day_status" || value.string.map(options.contains) == true
        }
        if key.hasPrefix("cups_") {
            if value == .null { return true }
            guard case .number(let number) = value else { return false }
            return number >= 0 && number <= 20 && number == Decimal(NSDecimalNumber(decimal: number).intValue)
        }
        if key == "blue_blocker_mdfd" {
            if value == .null { return true }
            let text: String
            if case .number(let number) = value {
                text = NSDecimalNumber(decimal: number).stringValue
            } else if let string = value.string {
                text = string
            } else {
                return false
            }
            guard let rating = Double(text), (0.1...9.9).contains(rating) else { return false }
            return text.range(of: #"^[0-9]+(?:\.[0-9])?$"#, options: .regularExpression) != nil
        }
        if case .bool = value { return true }
        return value == .null
            && !["caffeine_sensitive", "caffeine_non_user_opt_in", "exclude_caffeine", "flight_movement_breaks"]
                .contains(key)
    }
    static func apply(_ patch: JSONObject, section: SettingsSection, to settings: inout AccountSettings) {
        for (key, value) in patch.fields {
            switch section {
            case .bodyClock:
                if key == "blue_blocker_mdfd", case .number(let number) = value {
                    settings.bodyClock[camel(key)] = .string(NSDecimalNumber(decimal: number).stringValue)
                } else {
                    settings.bodyClock[camel(key)] = value
                }
            case .preferences: settings.preferences[camel(key)] = value
            case .reminders: settings.reminders[camel(key)] = value
            }
        }
        if section == .bodyClock {
            if patch.fields.keys.contains(where: {
                ["habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake"].contains($0)
            }) {
                settings.sleepAnswered = true
            }
            if settings.bodyClock["freeDayStatus"] != .string("declared") {
                settings.bodyClock["freeDayBed"] = .null
                settings.bodyClock["freeDayWake"] = .null
            }
            if settings.bodyClock["blueBlockers"] != .string("rated") { settings.bodyClock["blueBlockerMdfd"] = .null }
        }
    }
    static func readiness(_ body: JSONObject) -> JSONObject {
        ProfilePreferences.readiness(JSONObject(["invalidSections": .array([])]), bodyClock: body)
    }
}

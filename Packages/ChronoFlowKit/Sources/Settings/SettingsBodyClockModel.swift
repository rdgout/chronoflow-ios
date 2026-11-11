import AppCore
import Foundation
import Observation

public enum BodyClockGroup: String, CaseIterable, Sendable {
    case about, sleep, caffeine, light, health
    public var title: String {
        switch self {
        case .about: "About you"
        case .sleep: "Sleep schedule"
        case .caffeine: "Caffeine"
        case .light: "Light equipment"
        case .health: "Safety checks"
        }
    }
    public var fields: [String] {
        switch self {
        case .about: ["chronotype", "ageBand"]
        case .sleep: ["habitualBed", "habitualWake", "freeDayStatus", "freeDayBed", "freeDayWake"]
        case .caffeine:
            [
                "caffeineHabit", "cupsFilterCoffee", "cupsTea", "cupsCola", "cupsEnergyDrink", "caffeineSensitive",
                "caffeineNonUserOptIn", "excludeCaffeine",
            ]
        case .light: ["lightDevice", "blueBlockers", "blueBlockerMdfd"]
        case .health:
            ["shiftWork", "flightMovementBreaks"]
        }
    }
    public static func requestKey(_ field: String) -> String {
        field.reduce(into: "") { result, letter in
            if letter.isUppercase { result += "_" }
            result += letter.lowercased()
        }
    }
}

@MainActor @Observable public final class SettingsBodyClockModel {
    public private(set) var answers: JSONObject
    public private(set) var errors: [String: String] = [:]
    public private(set) var saved: Set<BodyClockGroup> = []
    public private(set) var failure = false
    @ObservationIgnored private var edits: [String: JSONValue] = [:]
    @ObservationIgnored private let save: @MainActor (JSONObject) async throws -> Void
    @ObservationIgnored private var revisions: [BodyClockGroup: Int] = [:]
    @ObservationIgnored private var tail: Task<Void, Never>?

    public init(answers: JSONObject, save: @escaping @MainActor (JSONObject) async throws -> Void) {
        self.answers = ProfilePreferences.bodyClock(answers)
        self.save = save
    }

    public func receive(_ value: JSONObject) {
        for (key, entry) in edits where value[key] == entry { edits[key] = nil }
        answers = ProfilePreferences.bodyClock(value)
        for (key, entry) in edits { answers[key] = entry }
    }

    public func change(_ group: BodyClockGroup, _ patch: [String: JSONValue]) async {
        guard Set(patch.keys).isSubset(of: group.fields) else { return }
        for (key, value) in patch {
            answers[key] = value
            edits[key] = value
        }
        normalize(group)
        let revision = (revisions[group] ?? 0) + 1
        revisions[group] = revision
        saved.remove(group)
        errors = errors.filter { !group.fields.contains($0.key) }
        let invalid = Self.validate(group, answers)
        errors.merge(invalid) { _, new in new }
        guard invalid.isEmpty else { return }
        let body = JSONObject(
            Dictionary(
                uniqueKeysWithValues: group.fields.map {
                    (BodyClockGroup.requestKey($0), answers[$0] ?? .null)
                }))
        let previous = tail
        let task = Task { [weak self, save] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await save(body)
                if self?.revisions[group] == revision { self?.saved.insert(group) }
                self?.failure = false
            } catch is CancellationError {
            } catch { self?.failure = true }
        }
        tail = task
        await task.value
    }

    private func normalize(_ group: BodyClockGroup) {
        func set(_ key: String, _ value: JSONValue) {
            answers[key] = value
            edits[key] = value
        }
        if group == .about, answers["ageBand"] == .string("unanswered") { set("ageBand", .null) }
        if group == .caffeine, answers["caffeineHabit"] == .string("unknown") { set("caffeineHabit", .null) }
        if group == .sleep, answers["freeDayStatus"]?.string != "declared" {
            set("freeDayBed", .null)
            set("freeDayWake", .null)
        }
        if group == .caffeine {
            for key in ["cupsFilterCoffee", "cupsTea", "cupsCola", "cupsEnergyDrink"] {
                if answers["caffeineHabit"]?.string != "cups" || answers[key] == .number(0) { set(key, .null) }
            }
        }
        if group == .light, answers["blueBlockers"]?.string != "rated" { set("blueBlockerMdfd", .null) }
        var drafts = answers["invalidDrafts"]?.object ?? [:]
        for key in group.fields where edits[key] != nil { drafts[BodyClockGroup.requestKey(key)] = nil }
        answers["invalidDrafts"] = .object(drafts)
    }

    public static func validate(_ group: BodyClockGroup, _ answers: JSONObject) -> [String: String] {
        var errors: [String: String] = [:]
        let choices: [String: Set<String>] = [
            "chronotype": ["early", "intermediate", "late"], "ageBand": ["under_18", "18_64", "65_plus"],
            "freeDayStatus": ["same_as_workdays", "declared", "unconfirmed"], "caffeineHabit": ["cups", "non_user"],
            "lightDevice": ["none", "box", "glasses"], "blueBlockers": ["no", "unrated", "rated"],
        ]
        for key in group.fields {
            guard let value = answers[key], value != .null else { continue }
            if let options = choices[key], !options.contains(value.string ?? "") {
                errors[key] = "Choose one of the available options."
            }
        }
        if group == .sleep {
            let pairs =
                [("habitualBed", "habitualWake")]
                + (answers["freeDayStatus"]?.string == "declared" ? [("freeDayBed", "freeDayWake")] : [])
            for (bed, wake) in pairs {
                let minutes = sleepMinutes(bed: answers[bed]?.string, wake: answers[wake]?.string)
                if minutes == nil || !(180...840).contains(minutes!) {
                    errors[bed] = "Check your bedtime and wake-up time."
                    errors[wake] = errors[bed]
                }
            }
        }
        if group == .caffeine {
            let counts = ["cupsFilterCoffee", "cupsTea", "cupsCola", "cupsEnergyDrink"].map { answers[$0] ?? .null }
            let valid = counts.allSatisfy { value in
                if value == .null { return true }
                if case .number(let number) = value {
                    return (0...20).contains(number) && number == Decimal(NSDecimalNumber(decimal: number).intValue)
                }
                return false
            }
            if !valid {
                errors["cupsFilterCoffee"] = "Choose one of the available options."
            } else if answers["caffeineHabit"]?.string == "cups",
                !counts.contains(where: {
                    if case .number(let value) = $0 { value > 0 } else { false }
                })
            {
                errors["cupsFilterCoffee"] = "Add at least one drink to save this answer."
            }
        }
        if group == .light, answers["blueBlockers"]?.string == "rated" {
            let value = answers["blueBlockerMdfd"]?.string ?? ""
            if value.range(of: #"^\d+(?:\.\d)?$"#, options: .regularExpression) == nil
                || !(0.1...9.9).contains(Double(value) ?? 0)
            {
                errors["blueBlockerMdfd"] = "Enter a rating between 0.1 and 9.9."
            }
        }
        for key in group.fields where answers["invalidDrafts"]?.object?[BodyClockGroup.requestKey(key)] != nil {
            errors[key] =
                group == .sleep ? "Check your bedtime and wake-up time." : "Choose one of the available options."
        }
        return errors
    }

    public static func sleepMinutes(bed: String?, wake: String?) -> Int? {
        func minutes(_ value: String?) -> Int? {
            guard let value, value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else {
                return nil
            }
            let parts = value.split(separator: ":").compactMap { Int($0) }
            return parts[0] * 60 + parts[1]
        }
        guard let bed = minutes(bed), let wake = minutes(wake) else { return nil }
        return (wake - bed + 1440) % 1440
    }
    deinit { tail?.cancel() }
}

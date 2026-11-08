import AppCore
import Foundation
import LocalStore
import PlanCore
import PlanUI

public struct SettingsCopy: Sendable, Equatable {
    public var key: String
    public var count: Int?
    public var values: [String: String]
    public init(_ key: String, count: Int? = nil, values: [String: String] = [:]) {
        self.key = key
        self.count = count
        self.values = values
    }
    public func text(language: Language) -> String {
        SettingsStrings.text(key, language: language, values, count: count)
    }
}

public struct PendingSettingsChange: Sendable, Equatable, Identifiable {
    public var id: String
    public var category: BlockType?
    public var copy: SettingsCopy

    @MainActor public func text(language: Language) -> String {
        var copy = copy
        if let step = copy.values["step"] {
            copy.values["step"] = PlanStrings.text(step, language: language)
        }
        return copy.text(language: language)
    }
}

public struct SettingsHomeState: Sendable, Equatable {
    public var account: AccountRecord?
    public var missingAnswers = 0
    public var credits: Int?
    public var pending: [PendingSettingsChange] = []
    public var pendingCount = 0
    public var outboxLoaded = false
    public init(account: AccountRecord? = nil, settings: [SettingsRecord] = [], outbox: [OutboxRecord] = []) {
        self.account = account
        apply(settings: settings)
        apply(outbox: outbox)
    }
    public var initials: String {
        let words = account?.name.split(whereSeparator: \.isWhitespace) ?? []
        return
            (String(words.first?.first.map(String.init) ?? "")
            + (words.count > 1 ? words.last?.first.map(String.init) ?? "" : "")).uppercased()
    }
    public mutating func apply(settings: [SettingsRecord]) {
        let readiness = try? settings.first { $0.section == "readiness" }?.value.decode(JSONObject.self)
        func count(_ key: String) -> Int {
            if case .array(let values) = readiness?[key] { return values.count }
            return 0
        }
        missingAnswers =
            readiness?["variant"]?.string == "needs-answers" ? count("missing") + count("invalidSections") : 0
        let plan = try? settings.first { $0.section == "planCredits" }?.value.decode(JSONObject.self)
        if case .bool(true) = plan?["unlimited"] {
            credits = nil
        } else if case .number(let number) = plan?["credits"], !number.isNaN,
            number >= 0, number < Decimal(Int.max)
        {
            credits = NSDecimalNumber(decimal: number).intValue
        } else {
            credits = nil
        }
    }
    public mutating func apply(outbox: [OutboxRecord]) {
        pendingCount = outbox.count
        outboxLoaded = true
        var indices: [String: Int] = [:]
        pending = []
        for row in outbox {
            var identity = row.id
            var category: BlockType?
            var copy = SettingsCopy("A change waiting to sync")
            var replace = false
            if case .checkOff(let check) = try? row.change {
                identity = "check:\(check.tripID):\(check.localDate):\(check.type.rawValue):\(check.ordinal)"
                category = check.type
                replace = true
                if check.status == .done, let step = stepLabelKey(check.type) {
                    copy = SettingsCopy("Checked off \"{{step}}\"", values: ["step": step])
                }
            } else if row.kind == OutboxKind.settings.rawValue,
                let payload = try? row.payload.decode(JSONObject.self), let section = payload["section"]?.string
            {
                let subsection = payload["bodyClockSection"]?.string
                identity = "settings:\(section):\(subsection ?? "")"
                if section == "bodyClock", subsection == "sleep" || Self.sleepPatch(payload) {
                    category = .sleep
                    copy = SettingsCopy("Changed your usual sleep times")
                }
            }
            let change = PendingSettingsChange(id: row.id, category: category, copy: copy)
            if let index = indices[identity] {
                if replace { pending[index] = change }
            } else {
                indices[identity] = pending.count
                pending.append(change)
            }
        }
    }
    private static func sleepPatch(_ payload: JSONObject) -> Bool {
        guard let patch = payload["patch"]?.object, !patch.isEmpty else { return false }
        return Set(patch.keys).isSubset(of: ["habitual_bed", "habitual_wake"])
    }

    public func syncCopy(now: Date, syncing: Bool = false, offline: Bool = false, zone: TimeZone = .current)
        -> SettingsCopy?
    {
        if syncing { return SettingsCopy("Syncing…") }
        if pendingCount > 0 { return SettingsCopy("%lld changes waiting to sync", count: pendingCount) }
        if offline { return SettingsCopy("Saved on this phone · syncs when you're online") }
        guard let raw = account?.syncedAt,
            let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                ?? (try? Date.ISO8601FormatStyle().parse(raw)), now.timeIntervalSince1970.isFinite
        else { return nil }
        let minutes = max(0, floor(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return SettingsCopy("Synced just now") }
        if minutes < 60 { return SettingsCopy("Synced %lld min ago", count: Int(minutes)) }
        if minutes < 1440 { return SettingsCopy("Synced %lld hours ago", count: Int(minutes / 60)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let days = max(
            1,
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
                ?? 1)
        if days == 1 { return SettingsCopy("Synced yesterday") }
        if days < 7 { return SettingsCopy("Synced %lld days ago", count: days) }
        return SettingsCopy("Synced on {{date}}", values: ["date": raw])
    }
}

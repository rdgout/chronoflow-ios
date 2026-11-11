import AppCore
import Foundation
import PlanCore

public struct ReminderSettings: Codable, Sendable, Equatable {
    public var light: Bool
    public var avoid: Bool
    public var caffeine: Bool
    public var winddown: Bool
    public var leadMin: Int

    public init(light: Bool = true, avoid: Bool = true, caffeine: Bool = true, winddown: Bool = true, leadMin: Int = 30)
    {
        self.light = light
        self.avoid = avoid
        self.caffeine = caffeine
        self.winddown = winddown
        self.leadMin = leadMin
    }
    public var enabled: Bool { light || avoid || caffeine || winddown }
    public func settingEnabled(_ enabled: Bool) -> Self {
        Self(light: enabled, avoid: enabled, caffeine: enabled, winddown: enabled, leadMin: leadMin)
    }
}

public enum ReminderPermission: String, Codable, Sendable, CaseIterable {
    case undetermined, granted, blocked, unsupported
    public func remindersActive(_ settings: ReminderSettings?) -> Bool { self == .granted && settings?.enabled == true }
}

public enum ReminderKind: String, Codable, Sendable {
    case seekLight = "seek_light"
    case avoidLight = "avoid_light"
    case caffeineCutoff = "caffeine_cutoff"
    case windDown = "wind_down"
}

public struct ReminderMember: Codable, Sendable, Equatable {
    public var kind: ReminderKind
    public var blockType: BlockType
    public var localDate: String
    public var ordinal: Int
    public var sendAt: Date
    public var blockStartUtc: Date
    public var displayTz: String
    public var expiresAt: Date
    public var identity: String { checkIdentity(CheckKeyView(type: blockType, localDate: localDate, ordinal: ordinal)) }
}

public struct ReminderDraft: Codable, Sendable, Equatable {
    public var members: [ReminderMember]
    public var sendAt: Date
    public var expiresAt: Date
    public var blockStartUtc: Date
    public var displayTz: String
    public var priority: Priority
}

public struct ReminderSelectionOptions: Sendable {
    public var coalesceMinutes = 15
    public var dailyCap = 6
    public var expiryGraceMinutes = 20
    public var sentMemberKeys: Set<String> = []
    public var sentCountsByDay: [String: Int] = [:]
    public var timeline: TimelinePresentationView?
    public init() {}
}

public func reminderLocalDay(_ date: Date, zone: String) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
}

public func reminderDrafts(
    _ blocks: [BlockView], settings: ReminderSettings, now: Date, options: ReminderSelectionOptions = .init()
) -> [ReminderDraft] {
    var keys: [String: CheckKeyView] = [:]
    var ordinals: [String: Int] = [:]
    for block in blocks where block.actionable {
        let day = reminderLocalDay(planDate(block.startUtc), zone: block.displayTz)
        let group = "\(block.type.rawValue)|\(day)"
        ordinals[group, default: 0] += 1
        keys[block.id] = CheckKeyView(type: block.type, localDate: day, ordinal: ordinals[group]!)
    }
    let sleeps = blocks.filter { $0.type == .sleep }.sorted { planDate($0.startUtc) < planDate($1.startUtc) }
    let ifYouCan = Set(
        options.timeline?.blockReasons.filter { $0.lines.contains { $0.key == "If you can" } }.map(\.blockId) ?? [])
    var drafts: [ReminderDraft] = []
    for block in blocks {
        guard let fallback = keys[block.id], block.priority == .core || block.priority == .recommended else { continue }
        let kind: ReminderKind?
        switch block.type {
        case .seekLight: kind = settings.light ? .seekLight : nil
        case .avoidLight: kind = settings.avoid && !ifYouCan.contains(block.id) ? .avoidLight : nil
        case .noCaffeine: kind = settings.caffeine ? .caffeineCutoff : nil
        case .sleep:
            if case .sleep(let params) = block.params, params.kind == .main, settings.winddown {
                kind = .windDown
            } else {
                kind = nil
            }
        default: kind = nil
        }
        guard let kind else { continue }
        let start = planDate(block.startUtc)
        let expires = min(planDate(block.endUtc), start.addingTimeInterval(Double(options.expiryGraceMinutes * 60)))
        guard expires > now else { continue }
        var send = max(start.addingTimeInterval(Double(-settings.leadMin * 60)), now)
        for sleep in sleeps where send >= planDate(sleep.startUtc) && send < planDate(sleep.endUtc) {
            send = planDate(sleep.endUtc)
        }
        guard send < expires else { continue }
        let key = block.checkKey ?? fallback
        guard !options.sentMemberKeys.contains(checkIdentity(key)) else { continue }
        drafts.append(
            ReminderDraft(
                members: [
                    ReminderMember(
                        kind: kind, blockType: key.type, localDate: key.localDate, ordinal: key.ordinal,
                        sendAt: send, blockStartUtc: start, displayTz: block.displayTz, expiresAt: expires)
                ],
                sendAt: send, expiresAt: expires, blockStartUtc: start, displayTz: block.displayTz,
                priority: block.priority))
    }
    drafts.sort { $0.sendAt == $1.sendAt ? $0.blockStartUtc < $1.blockStartUtc : $0.sendAt < $1.sendAt }
    var merged: [ReminderDraft] = []
    for draft in drafts {
        if let previous = merged.last,
            draft.sendAt <= previous.sendAt.addingTimeInterval(Double(options.coalesceMinutes * 60))
        {
            let index = merged.count - 1
            merged[index].members += draft.members
            merged[index].expiresAt = max(previous.expiresAt, draft.expiresAt)
            merged[index].priority = previous.priority == .core ? .core : draft.priority
        } else {
            merged.append(draft)
        }
    }
    merged.sort { $0.priority == $1.priority ? $0.blockStartUtc < $1.blockStartUtc : $0.priority == .core }
    var counts = options.sentCountsByDay
    return merged.filter { draft in
        let day = reminderLocalDay(draft.blockStartUtc, zone: draft.displayTz)
        guard counts[day, default: 0] < options.dailyCap else { return false }
        counts[day, default: 0] += 1
        return true
    }.sorted { $0.sendAt < $1.sendAt }
}

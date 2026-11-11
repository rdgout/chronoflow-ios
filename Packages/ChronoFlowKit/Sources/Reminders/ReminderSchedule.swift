import AppCore
import Foundation
import LocalStore
import PlanCore

public struct ReminderPlan: Sendable {
    public var card: TripCardView
    public var detail: TripDetail
    public var marks: [CheckMark]
    public init(card: TripCardView, detail: TripDetail, marks: [CheckMark] = []) {
        self.card = card
        self.detail = detail
        self.marks = marks
    }
}

public struct ReminderRequest: Codable, Sendable, Equatable {
    public var identifier: String
    public var title: String
    public var body: String
    public var sendAt: Date
    public var tripID: String
    public var blockID: String
    public var inputHash: String
    public var memberKeys: [String]
    public var accountID: String? = nil
}

public protocol ReminderNotificationCenter: Sendable {
    func permission() async -> ReminderPermission
    func requestPermission() async throws -> ReminderPermission
    func pending() async -> [ReminderRequest]
    func add(_ request: ReminderRequest) async throws
    func remove(_ identifiers: [String]) async
    func removeDelivered() async
}

public enum ReminderStrings {
    public static func text(_ key: String, language: Language, time: String? = nil, count: Int? = nil) -> String {
        let bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj").flatMap(Bundle.init(url:))
            ?? .module
        var result = bundle.localizedString(forKey: key, value: key, table: "Reminders")
        if let count {
            result = result.replacingOccurrences(
                of: "{{count}}", with: count.formatted(.number.locale(Locale(identifier: language.rawValue))))
        }
        return time.map { result.replacingOccurrences(of: "{{time}}", with: $0) } ?? result
    }
}

public func reminderRequests(
    plans: [ReminderPlan], accountID: String, settings: ReminderSettings, ledger: [ReminderLedgerEntry],
    now: Date, language: Language, timeFormat: TimeFormat, formatter: CopyLineFormatter
) -> [ReminderRequest] {
    let elapsedLedger = ReminderLedger.elapsed(ledger, now: now)
    var requests: [ReminderRequest] = []
    for value in plans where value.card.progress.status != .completed {
        let detail = value.detail
        let plan = withoutOptionalSteps(detail.plan)
        var options = ReminderSelectionOptions()
        options.timeline = detail.timeline
        options.sentMemberKeys = Set(buildCheckState(plan, marks: value.marks).marks.map { checkIdentity($0.key) })
        let elapsed = reminderDrafts(
            plan.blocks, settings: settings, now: now.addingTimeInterval(-36 * 60 * 60),
            options: {
                var lookback = ReminderSelectionOptions()
                lookback.timeline = detail.timeline
                return lookback
            }()
        ).filter { $0.sendAt <= now.addingTimeInterval(5) }
        for draft in elapsed {
            options.sentCountsByDay[reminderLocalDay(draft.blockStartUtc, zone: draft.displayTz), default: 0] += 1
            for member in draft.members where member.sendAt <= now.addingTimeInterval(5) {
                options.sentMemberKeys.insert(member.identity)
            }
        }
        for entry in elapsedLedger where entry.tripId == value.card.id && entry.inputHash == plan.meta.inputHash {
            options.sentMemberKeys.formUnion(entry.memberKeys)
        }
        for draft in reminderDrafts(plan.blocks, settings: settings, now: now, options: options)
        where draft.sendAt > now.addingTimeInterval(5) && draft.sendAt <= now.addingTimeInterval(48 * 60 * 60) {
            let members = draft.members.sorted { $0.blockStartUtc < $1.blockStartUtc }
            var announced: Set<String> = []
            let format = CopyFormat(
                language: language, timeFormat: timeFormat, displayZone: draft.displayTz, annotateInstantZone: true,
                trip: detail.trip)
            let body = members.compactMap { member -> String? in
                guard announced.insert(member.kind.rawValue).inserted else { return nil }
                let key: String
                switch member.kind {
                case .seekLight: key = "Seek bright light from {{time}}."
                case .avoidLight: key = "Avoid bright light from {{time}}."
                case .caffeineCutoff: key = "Last caffeine before {{time}}."
                case .windDown: key = "Wind down for bed: sleep from {{time}}."
                }
                var time = formatter.formatInstant(
                    member.blockStartUtc.ISO8601Format(), options: format, zone: member.displayTz)
                if member.displayTz != draft.displayTz {
                    time += " (\(zoneLabel(member.displayTz, trip: detail.trip)))"
                }
                return ReminderStrings.text(key, language: language, time: time).replacingOccurrences(
                    of: #"\.+$"#, with: "", options: .regularExpression) + "."
            }.joined(separator: " ")
            let keys = draft.members.map(\.identity)
            let identity = ([accountID, value.card.id, plan.meta.inputHash] + keys).joined(separator: "\n")
            let identifier = "chronoflow.reminder." + Data(identity.utf8).base64EncodedString()
            let first = draft.members[0]
            let block =
                plan.blocks.first { $0.checkKey.map(checkIdentity) == first.identity }
                ?? plan.blocks.first { $0.type == first.blockType && planDate($0.startUtc) == first.blockStartUtc }
            requests.append(
                ReminderRequest(
                    identifier: identifier,
                    title:
                        "\(value.card.from.city ?? value.card.from.iata) → \(value.card.to.city ?? value.card.to.iata)",
                    body: body, sendAt: draft.sendAt, tripID: value.card.id, blockID: block?.id ?? "",
                    inputHash: plan.meta.inputHash, memberKeys: keys, accountID: accountID))
        }
    }
    return Array(
        requests.sorted { $0.sendAt == $1.sendAt ? $0.identifier < $1.identifier : $0.sendAt < $1.sendAt }.prefix(60))
}

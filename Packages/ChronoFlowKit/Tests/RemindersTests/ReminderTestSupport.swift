import AppCore
import Foundation
import LocalStore
import PlanCore

@testable import Reminders

let reminderNow = planDate("2026-10-14T00:00:00Z")
let reminderAccount = "01900000-0000-7000-8000-000000000001"

func reminderBlock(_ hours: Double = 1, type: BlockType = .seekLight, ordinal: Int = 1, zone: String = "UTC")
    -> BlockView
{
    let start = reminderNow.addingTimeInterval(hours * 3600)
    let params: BlockParams
    switch type {
    case .sleep: params = .sleep(SleepParamsView(kind: .main, setting: .bed, opportunityMin: 60))
    case .seekLight: params = .seekLight(SeekLightParamsView(source: .outdoor, coreMin: 30))
    case .avoidLight: params = .avoidLight(AvoidLightParamsView(setting: .home, reduced: false))
    case .noCaffeine: params = .noCaffeine(NoCaffeineParamsView())
    default: params = .unknown(.null)
    }
    return BlockView(
        id: "\(type.rawValue)-\(hours)", lane: .light, type: type,
        startUtc: start.ISO8601Format(.init(includingFractionalSeconds: true)),
        endUtc: start.addingTimeInterval(3600).ISO8601Format(), displayTz: zone, priority: .recommended,
        text: CopyLine(key: "test", args: []), params: params,
        actionable: true,
        checkKey: CheckKeyView(type: type, localDate: reminderLocalDay(start, zone: zone), ordinal: ordinal))
}
func reminderPlan(
    _ blocks: [BlockView] = [reminderBlock()], id: String = "trip", hash: String = "hash", marks: [CheckMark] = []
) -> ReminderPlan {
    let from = AirportRef(iata: "AMS", city: "Amsterdam", zone: "Europe/Amsterdam")
    let to = AirportRef(iata: "HND", city: "Tokyo", zone: "Asia/Tokyo")
    let card = TripCardView(
        id: id, from: from, to: to, departLocal: "2026-10-14T00:00", arriveLocal: "2026-10-14T14:00",
        departureUtc: "2026-10-14T00:00:00Z", arrivalUtc: "2026-10-14T05:00:00Z", connections: [],
        offsetDifferenceMinutes: 540, progress: TripProgress(status: .active), canComplete: false, canReopen: false,
        canEdit: false, canDuplicate: false, canDelete: false)
    return ReminderPlan(
        card: card,
        detail: TripDetail(
            trip: TripDetailView(
                id: id, from: from, to: to, departLocal: card.departLocal, departureUtc: card.departureUtc,
                endUtc: "2026-10-17T00:00:00Z", offsetDifferenceMin: 540, legs: []),
            plan: PlanView(
                status: .ok, reasons: [], prompts: [], meta: PlanMeta(inputHash: hash), days: [], blocks: blocks,
                warnings: []),
            notices: PlanNoticesView(days: [], unassignedWarningIndexes: []),
            timeline: TimelinePresentationView(days: [], blockReasons: [], transferWarnings: []),
            checkState: CheckState(planInputHash: hash, marks: [], days: []), detailVersion: "1"), marks: marks)
}

actor FakeReminderCenter: ReminderNotificationCenter {
    var status: ReminderPermission = .granted
    var requests: [String: ReminderRequest] = [:]
    var adds: [ReminderRequest] = []
    var removals: [String] = []
    var rejects: Set<String> = []
    var pause: CheckedContinuation<Void, Never>?
    var pausesNext = false
    var adding = false
    var maximumConcurrentAdds = 0
    private var activeAdds = 0
    func permission() -> ReminderPermission { status }
    func requestPermission() -> ReminderPermission {
        status = .granted
        return status
    }
    func pending() -> [ReminderRequest] { Array(requests.values) }
    func add(_ request: ReminderRequest) async throws {
        adding = true
        activeAdds += 1
        maximumConcurrentAdds = max(maximumConcurrentAdds, activeAdds)
        defer { activeAdds -= 1 }
        if pausesNext {
            pausesNext = false
            await withCheckedContinuation { pause = $0 }
        }
        adding = false
        if rejects.contains(request.blockID) { throw CancellationError() }
        requests[request.identifier] = request
        adds.append(request)
    }
    func remove(_ identifiers: [String]) {
        removals += identifiers
        for id in identifiers { requests[id] = nil }
    }
    func removeDelivered() {}
    func setPermission(_ status: ReminderPermission) { self.status = status }
    func holdNext() { pausesNext = true }
    func release() {
        pause?.resume()
        pause = nil
    }
    func reject(_ id: String) { rejects.insert(id) }
}

struct ReminderTestStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let database: AccountDatabase
    init() async throws {
        database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: reminderAccount)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: reminderAccount, name: "Demo", email: "demo@example.com"))
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
    }
    func store(_ value: ReminderPlan) async throws {
        try await TripRepository(database: database).upsert(
            TripRecord(
                id: value.card.id, card: .encoding(value.card), currentInputHash: value.detail.plan.meta.inputHash,
                keepOffline: true, departureUtc: value.card.departureUtc))
        try await TripRepository(database: database).store(
            plan: PlanVersionRecord(
                tripId: value.card.id, inputHash: value.detail.plan.meta.inputHash, detail: .encoding(value.detail),
                receivedAt: reminderNow.ISO8601Format()),
            checks: value.marks.map {
                CheckMarkRecord(
                    tripId: value.card.id, inputHash: value.detail.plan.meta.inputHash, type: $0.key.type.rawValue,
                    localDate: $0.key.localDate, ordinal: $0.key.ordinal, status: $0.status.rawValue,
                    markedAt: $0.markedAt)
            })
    }
    func close() async throws {
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }
}

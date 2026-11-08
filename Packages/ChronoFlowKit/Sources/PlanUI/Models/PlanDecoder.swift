import AppCore
import Foundation
import LocalStore
import PlanCore

public nonisolated struct TripListValue: Sendable, Equatable {
    public var card: TripCardView
    public var planStartUtc: String?
    public var planEndUtc: String?
    public var status: TripStatus
    public var planStartZone: String? = nil
    public var planEndDate: String? = nil
    public var preparationDays: Int? = nil

    public init(
        card: TripCardView, planStartUtc: String?, planEndUtc: String?, status: TripStatus,
        planStartZone: String? = nil, planEndDate: String? = nil, preparationDays: Int? = nil
    ) {
        self.card = card
        self.planStartUtc = planStartUtc
        self.planEndUtc = planEndUtc
        self.status = status
        self.planStartZone = planStartZone
        self.planEndDate = planEndDate
        self.preparationDays = preparationDays
    }
}

public actor PlanDecoder {
    private struct Key: Hashable {
        var trip: String
        var inputHash: String
        var version: String?
    }
    private var layoutCache: [String: (PlanView, TimelinePresentationView, [BlockType], [String: DayLayout])] = [:]
    private var preparedCache: [String: (TripDetail, Language, TimeFormat, [CheckMark], [BlockType], PreparedPlan)] =
        [:]
    private var formatter: CopyLineFormatter?
    public private(set) var layoutCount = 0
    private var cache: [Key: (Data, TripDetail)] = [:]
    public private(set) var decodeCount = 0
    public private(set) var decodedOnMainThread = false
    public init() {}

    public func trips(_ records: [TripRecord], now: Date) -> (values: [TripListValue], error: (any Error)?) {
        assertWorker()
        var values: [TripListValue] = []
        var firstError: (any Error)?
        for record in records where record.deletedAt == nil && !record.deletedLocally {
            do {
                let card = try record.card.decode(TripCardView.self)
                values.append(
                    TripListValue(
                        card: card, planStartUtc: record.planStartUtc, planEndUtc: record.planEndUtc,
                        status: tripDisplayStatus(
                            card, planStartUtc: record.planStartUtc, planEndUtc: record.planEndUtc, now: now),
                        planStartZone: record.planStartZone,
                        planEndDate: record.planEndDate, preparationDays: record.preparationDays))
            } catch { firstError = firstError ?? error }
        }
        return (values, firstError)
    }

    public func detail(_ record: PlanVersionRecord) throws -> TripDetail {
        assertWorker()
        let key = Key(trip: record.tripId, inputHash: record.inputHash, version: record.detailVersion)
        if let cached = cache[key], cached.0 == record.detail.data { return cached.1 }
        let detail = try record.decodedDetail()
        decodeCount += 1
        cache = cache.filter { $0.key.trip != record.tripId }
        cache[key] = (record.detail.data, detail)
        return detail
    }

    public func detail(_ snapshot: TripPlanSnapshot) throws -> TripDetail? {
        guard let record = snapshot.plan else { return nil }
        var value = try detail(record)
        var marks: [String: CheckMark] = [:]
        for row in snapshot.checks where row.inputHash == record.inputHash {
            let key = CheckKeyView(type: BlockType(rawValue: row.type), localDate: row.localDate, ordinal: row.ordinal)
            marks[checkIdentity(key)] = CheckMark(
                key: key, status: CheckStatus(rawValue: row.status), markedAt: row.markedAt)
        }
        for change in snapshot.pendingChecks {
            let key = CheckKeyView(type: change.type, localDate: change.localDate, ordinal: change.ordinal)
            if let status = change.status {
                marks[checkIdentity(key)] = CheckMark(key: key, status: status, markedAt: "")
            } else {
                marks.removeValue(forKey: checkIdentity(key))
            }
        }
        value.checkState = buildCheckState(
            value.plan, marks: marks.values.sorted { checkIdentity($0.key) < checkIdentity($1.key) })
        return value
    }

    public func layouts(_ detail: TripDetail, hidden: [BlockType]) -> [String: DayLayout] {
        assertWorker()
        let id = detail.trip.id
        if let cached = layoutCache[id], cached.0 == detail.plan, cached.1 == detail.timeline, cached.2 == hidden {
            return cached.3
        }
        let result = layoutPlan(withoutOptionalSteps(detail.plan), timeline: detail.timeline, hidden: hidden)
        layoutCache[id] = (detail.plan, detail.timeline, hidden, result)
        layoutCount += 1
        return result
    }

    public func evict(tripID: String) {
        cache = cache.filter { $0.key.trip != tripID }
        layoutCache[tripID] = nil
        preparedCache[tripID] = nil
    }

    public func card(_ record: TripRecord) throws -> TripCardView { try record.card.decode(TripCardView.self) }

    public func prepare(
        _ detail: TripDetail, hidden: [BlockType], language: Language, timeFormat: TimeFormat, marks: [CheckMark]
    ) async throws -> PreparedPlan {
        let id = detail.trip.id
        if let c = preparedCache[id], c.0 == detail, c.1 == language, c.2 == timeFormat, c.3 == marks, c.4 == hidden {
            return c.5
        }
        if formatter == nil { formatter = CopyLineFormatter(catalog: try await CopyCatalog.load()) }
        let result = preparePlan(
            detail, layouts: layouts(detail, hidden: hidden), formatter: formatter!, language: language,
            timeFormat: timeFormat, marks: marks)
        preparedCache[id] = (detail, language, timeFormat, marks, hidden, result)
        return result
    }

    private func assertWorker() {
        decodedOnMainThread = decodedOnMainThread || Thread.isMainThread
        precondition(!Thread.isMainThread, "Plan decoding must run off the main thread")
    }
}

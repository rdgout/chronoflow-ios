import AppCore
import Foundation
import LocalStore
import PlanCore

public struct TripListValue: Sendable, Equatable {
    public var card: TripCardView
    public var planStartUtc: String?
    public var planEndUtc: String?
    public var status: TripStatus
}

public actor PlanDecoder {
    private struct Key: Hashable {
        var trip: String
        var inputHash: String
        var version: String?
    }
    private var cache: [Key: (Data, TripDetail)] = [:]
    public private(set) var decodeCount = 0
    public private(set) var decodedOnMainThread = false
    public init() {}

    public func trips(_ records: [TripRecord], now: Date) throws -> [TripListValue] {
        assertWorker()
        return try records.filter { $0.deletedAt == nil && !$0.deletedLocally }.map { record in
            let card = try record.card.decode(TripCardView.self)
            return TripListValue(
                card: card, planStartUtc: record.planStartUtc, planEndUtc: record.planEndUtc,
                status: tripDisplayStatus(
                    card, planStartUtc: record.planStartUtc, planEndUtc: record.planEndUtc, now: now))
        }
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

    public func layouts(_ detail: TripDetail, hidden: [BlockType]) -> [String: DayLayout] {
        layoutPlan(withoutOptionalSteps(detail.plan), timeline: detail.timeline, hidden: hidden)
    }

    public func evict(tripID: String) { cache = cache.filter { $0.key.trip != tripID } }

    private func assertWorker() {
        decodedOnMainThread = decodedOnMainThread || Thread.isMainThread
        precondition(!Thread.isMainThread, "Plan decoding must run off the main thread")
    }
}

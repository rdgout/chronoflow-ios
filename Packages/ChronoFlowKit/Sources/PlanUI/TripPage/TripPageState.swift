import AppCore
import Foundation
import PlanCore

nonisolated public enum TripPageState: String, CaseIterable, Sendable {
    case loading, remoteLoading, remoteOffline, ready, noPlan, notFound, server

    public static func resolve(
        keepOffline: Bool, stored: Bool, noPlan: Bool = false, online: Bool,
        fetch: TripPageFetch, missingAfterSync: Bool = false, tombstoned: Bool = false,
        awaitingSync: Bool = false
    ) -> Self {
        if tombstoned { return .notFound }
        if stored { return noPlan ? .noPlan : .ready }
        if awaitingSync { return .loading }
        if missingAfterSync { return .notFound }
        if keepOffline { return .loading }
        if !online { return .remoteOffline }
        switch fetch {
        case .notFound: return .notFound
        case .failed: return .server
        default: return .remoteLoading
        }
    }
}

nonisolated public enum TripPageFetch: Sendable { case idle, loading, loaded, notFound, failed }

nonisolated public struct TripPageAnchor: Sendable, Equatable {
    public var dayID: String?
    public var labelDate: String?
    public var offset: Double
    public init(dayID: String? = nil, labelDate: String? = nil, offset: Double = 0) {
        self.dayID = dayID
        self.labelDate = labelDate
        self.offset = offset
    }
}

nonisolated public func openingDay(
    _ days: [DayView], blocks: [BlockView], requestedDay: String?, blockID: String?, keptDay: String?, now: Date
) -> DayView? {
    if let day = days.first(where: { $0.id == requestedDay }) { return day }
    if let block = blocks.first(where: { $0.id == blockID }),
        let day = days.first(where: {
            planDate($0.startUtc) <= planDate(block.startUtc) && planDate(block.startUtc) < planDate($0.endUtc)
        })
    {
        return day
    }
    if let day = days.first(where: { $0.id == keptDay }) { return day }
    if let day = days.first(where: { planDate($0.startUtc) <= now && now < planDate($0.endUtc) }) { return day }
    if let day = days.last, now >= planDate(day.endUtc) { return day }
    return days.first
}

nonisolated public func replacementAnchor(_ anchor: TripPageAnchor, days: [DayView]) -> TripPageAnchor {
    guard let date = anchor.labelDate,
        let day = days.first(where: { $0.labelDate == date })
            ?? days.min(by: {
                abs(planDate($0.labelDate + "T12:00:00Z").timeIntervalSince(planDate(date + "T12:00:00Z")))
                    < abs(planDate($1.labelDate + "T12:00:00Z").timeIntervalSince(planDate(date + "T12:00:00Z")))
            })
    else { return TripPageAnchor(dayID: days.first?.id, labelDate: days.first?.labelDate) }
    return TripPageAnchor(dayID: day.id, labelDate: day.labelDate, offset: anchor.offset)
}

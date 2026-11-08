import AppCore
import Foundation
import PlanCore

public func selectTodayTrip(_ trips: [TripListValue], now: Date) -> TripListValue? {
    trips.filter { status($0, now) != .completed }.sorted { a, b in
        let activeA = status(a, now) == .active
        let activeB = status(b, now) == .active
        if activeA != activeB { return activeA }
        let startA = planDate(activeA ? a.planEndUtc ?? a.card.arrivalUtc : a.planStartUtc ?? a.card.departureUtc)
        let startB = planDate(activeB ? b.planEndUtc ?? b.card.arrivalUtc : b.planStartUtc ?? b.card.departureUtc)
        return startA == startB ? a.card.id < b.card.id : startA < startB
    }.first
}

public func lastEndedTrip(_ trips: [TripListValue], now: Date) -> TripListValue? {
    trips.filter { status($0, now) == .completed }.sorted { a, b in
        let endA = min(planDate(a.planEndUtc ?? a.card.arrivalUtc), now)
        let endB = min(planDate(b.planEndUtc ?? b.card.arrivalUtc), now)
        return endA == endB ? a.card.id < b.card.id : endA > endB
    }.first
}

private func status(_ trip: TripListValue, _ now: Date) -> TripStatus {
    tripDisplayStatus(trip.card, planStartUtc: trip.planStartUtc, planEndUtc: trip.planEndUtc, now: now)
}

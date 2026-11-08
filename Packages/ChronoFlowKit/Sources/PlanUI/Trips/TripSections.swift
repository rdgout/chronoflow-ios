import AppCore
import PlanCore

public struct TripSection {
    public var status: TripStatus
    public var trips: [TripListValue]
}

public func tripSections(_ trips: [TripListValue]) -> [TripSection] {
    [TripStatus.active, .upcoming, .completed].compactMap { status in
        let values = trips.filter { $0.status == status }.sorted { a, b in
            let departureA = planDate(a.card.departureUtc)
            let departureB = planDate(b.card.departureUtc)
            return departureA == departureB ? a.card.id > b.card.id : departureA > departureB
        }
        return values.isEmpty ? nil : TripSection(status: status, trips: values)
    }
}

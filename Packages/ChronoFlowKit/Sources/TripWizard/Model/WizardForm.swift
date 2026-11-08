import AppCore
import Foundation

public struct WizardLeg: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var fromIata = ""
    public var fromCity: String?
    public var toIata = ""
    public var toCity: String?
    public var departLocal = ""
    public var arriveLocal = ""
    public var flightNumber: String?
    public var seatLieFlat = false
    public var seatWindow: String?
    public var leaveForAirportLocal: String?
    public var airportTransferMin: Int?
    public init(fromIata: String = "", fromCity: String? = nil) {
        self.fromIata = fromIata
        self.fromCity = fromCity
    }
}

public struct WizardBusy: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var startLocal: String
    public var endLocal: String
    public init(id: String = UUID().uuidString, startLocal: String, endLocal: String) {
        self.id = id
        self.startLocal = startLocal
        self.endLocal = endLocal
    }
    var input: ApiTripInputBusy { ApiTripInputBusy(startLocal: startLocal, endLocal: endLocal) }
}

public struct WizardStay: Codable, Sendable, Equatable {
    public var bedAvailableMode: String? = "arrival"
    public var bedAvailableFromLocal: String?
    public var checkOutLocal: String?
    public var lateCheckOutOrDayRoom = false
    public var arrivalTransferMin: Int?
    public var transferMode: String?
    public var busyIntervals: [WizardBusy] = []
    public init() {}
}

public struct WizardEnd: Codable, Sendable, Equatable {
    public var kind = "one_way"
    public var nights: Int?
    public var checkOutDate: String?
    public var returnFromLeg: Int?
    public init() {}
}

public struct WizardSleepOverride: Codable, Sendable, Equatable {
    public var enabled = false
    public var habitualBed: String?
    public var habitualWake: String?
    public var chronotype: String?
    public init() {}
}

public struct WizardPreparation: Codable, Sendable, Equatable {
    public var days = 3
    public var fastDelayOptIn = false
    public var latestWake: String?
    public var feasibleNightBed: String?
    public var feasibleNightWake: String?
    public var busyAnswered = false
    public var busyIntervals: [WizardBusy] = []
    public init() {}
}

public struct WizardForm: Codable, Sendable, Equatable {
    public static var maxFlights: Int { 16 }
    public static var maxPreparationDays: Int { 4 }
    public var legs: [WizardLeg] = [WizardLeg()]
    public var stays: [WizardStay] = [WizardStay()]
    public var end = WizardEnd()
    public var override = WizardSleepOverride()
    public var preparation = WizardPreparation()
    public var identity: ApiReviewIdentity?
    public var itinerary: ApiReviewItinerary?
    public init() {}
    public var returnBoundary: Int { end.kind == "return_legs" ? end.returnFromLeg ?? legs.count : legs.count }

    public mutating func updateLeg(_ index: Int, _ update: (inout WizardLeg) -> Void) {
        guard legs.indices.contains(index) else { return }
        let before = legs[index].toIata
        let beforeCity = legs[index].toCity
        update(&legs[index])
        if end.kind == "return_legs", index == returnBoundary - 1, legs.indices.contains(returnBoundary),
            legs[index].toIata != before || legs[index].toCity != beforeCity
        {
            legs[returnBoundary].fromIata = legs[index].toIata
            legs[returnBoundary].fromCity = legs[index].toCity
        }
        itinerary = nil
    }

    public mutating func addFlight(home: Bool = false) {
        guard legs.count < Self.maxFlights, !home || end.kind == "return_legs" else { return }
        let index = home ? legs.count : returnBoundary
        let previous = legs[index - 1]
        legs.insert(WizardLeg(fromIata: previous.toIata, fromCity: previous.toCity), at: index)
        stays.insert(WizardStay(), at: index)
        if end.kind == "return_legs", !home { end.returnFromLeg = returnBoundary + 1 }
        itinerary = nil
    }

    public struct RemovedFlight: Sendable {
        public var index: Int
        public var outbound: Bool
        public var leg: WizardLeg
        public var stay: WizardStay
    }

    @discardableResult public mutating func takeFlight(_ index: Int) -> RemovedFlight? {
        let boundary = returnBoundary
        let outbound = index < boundary
        guard legs.indices.contains(index), (outbound ? boundary : legs.count - boundary) > 1 else { return nil }
        let removed = RemovedFlight(
            index: index, outbound: outbound, leg: legs.remove(at: index), stay: stays.remove(at: index))
        if end.kind == "return_legs", outbound { end.returnFromLeg = boundary - 1 }
        itinerary = nil
        return removed
    }

    public mutating func restoreFlight(_ removed: RemovedFlight) {
        guard !legs.contains(where: { $0.id == removed.leg.id }), legs.count < Self.maxFlights,
            removed.outbound || end.kind == "return_legs"
        else { return }
        let index =
            removed.outbound ? min(removed.index, returnBoundary) : min(legs.count, max(removed.index, returnBoundary))
        let boundary = returnBoundary
        legs.insert(removed.leg, at: index)
        stays.insert(removed.stay, at: index)
        if end.kind == "return_legs", removed.outbound { end.returnFromLeg = boundary + 1 }
        itinerary = nil
    }

    public struct RetainedReturn: Sendable {
        public var legs: [WizardLeg]
        public var stays: [WizardStay]
    }

    public mutating func addReturn(_ retained: RetainedReturn? = nil) {
        guard end.kind != "return_legs", legs.count + (retained?.legs.count ?? 1) <= Self.maxFlights,
            let last = legs.last
        else { return }
        var returned = retained ?? RetainedReturn(legs: [WizardLeg()], stays: [WizardStay()])
        guard !returned.legs.isEmpty else { return }
        returned.legs[0].fromIata = last.toIata
        returned.legs[0].fromCity = last.toCity
        end.returnFromLeg = legs.count
        end.kind = "return_legs"
        legs += returned.legs
        stays += returned.stays
        itinerary = nil
    }

    @discardableResult public mutating func removeReturn() -> RetainedReturn {
        let boundary = returnBoundary
        let retained = RetainedReturn(legs: Array(legs.dropFirst(boundary)), stays: Array(stays.dropFirst(boundary)))
        legs = Array(legs.prefix(boundary))
        stays = Array(stays.prefix(boundary))
        end.kind = end.nights != nil ? "nights" : end.checkOutDate != nil ? "check_out" : "one_way"
        end.returnFromLeg = nil
        itinerary = nil
        return retained
    }

    public mutating func insertStop(_ airport: ApiAirportSuggestion, beforeDestinationOf index: Int) {
        guard legs.indices.contains(index), legs.count < Self.maxFlights else { return }
        let original = legs[index]
        var next = WizardLeg(fromIata: airport.iata, fromCity: airport.city)
        next.toIata = original.toIata
        next.toCity = original.toCity
        next.arriveLocal = original.arriveLocal
        legs[index].toIata = airport.iata
        legs[index].toCity = airport.city
        legs[index].arriveLocal = ""
        legs.insert(next, at: index + 1)
        stays.insert(WizardStay(), at: index)
        if end.kind == "return_legs", index < returnBoundary { end.returnFromLeg = returnBoundary + 1 }
        itinerary = nil
    }

    public mutating func removeStop(at index: Int) {
        guard index > 0, legs.indices.contains(index), index != returnBoundary else { return }
        let last = legs[index]
        legs[index - 1].toIata = last.toIata
        legs[index - 1].toCity = last.toCity
        legs[index - 1].arriveLocal = last.arriveLocal
        legs.remove(at: index)
        stays.remove(at: index - 1)
        if end.kind == "return_legs", index < returnBoundary { end.returnFromLeg = returnBoundary - 1 }
        itinerary = nil
    }
}

import AppCore

public struct WizardRouteAirport: Sendable, Equatable {
    public var iata: String
    public var city: String?
}

extension WizardForm {
    public func route(home: Bool = false) -> [WizardRouteAirport] {
        let flights = home ? Array(legs.dropFirst(returnBoundary)) : Array(legs.prefix(returnBoundary))
        guard let first = flights.first else { return [] }
        return [WizardRouteAirport(iata: first.fromIata, city: first.fromCity)]
            + flights.map { WizardRouteAirport(iata: $0.toIata, city: $0.toCity) }
    }

    public func routeComplete(home: Bool = false) -> Bool {
        let airports = route(home: home)
        return airports.count > 1 && !airports.contains { $0.iata.isEmpty }
            && airports.first?.iata != airports.last?.iata
            && zip(airports, airports.dropFirst()).allSatisfy { $0.iata != $1.iata }
    }

    public mutating func setRouteAirport(_ airport: ApiAirportSuggestion, at position: Int, home: Bool = false) {
        let airports = route(home: home)
        guard airports.indices.contains(position), !home || position > 0 else { return }
        let start = home ? returnBoundary : 0
        if position > 0 {
            updateLeg(start + position - 1) {
                $0.toIata = airport.iata
                $0.toCity = airport.city
            }
        }
        if position < airports.count - 1 {
            updateLeg(start + position) {
                $0.fromIata = airport.iata
                $0.fromCity = airport.city
            }
        }
    }

    public mutating func makeDirect(home: Bool = false) {
        let start = home ? returnBoundary : 0
        while (home ? legs.count - returnBoundary : returnBoundary) > 1 {
            removeStop(at: start + 1)
        }
    }
}

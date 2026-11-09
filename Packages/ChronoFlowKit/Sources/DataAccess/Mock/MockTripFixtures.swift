import AppCore
import CryptoKit
import Foundation

extension MockTripFixtures {
    struct Template: Codable, Sendable {
        var card: TripCardView
        var detail: TripDetail
    }
    struct Collection: Decodable { let trips: [Template] }
    static func templates() throws -> [Template] {
        try JSONDecoder().decode(Collection.self, from: fixtureData()).trips
    }
    static func rebase(_ fixture: Template, days: Int, minutes: Int = 0) throws -> Template {
        let utcFormatter = ISO8601DateFormatter()
        func instant(_ value: String) -> Date {
            let normalized = value.count == 17 ? value.replacingOccurrences(of: "Z", with: ":00Z") : value
            return utcFormatter.date(from: normalized)!
        }
        let zone = TimeZone(identifier: fixture.card.from.zone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = zone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        func transform(_ value: Any, zone: String) -> Any {
            if let object = value as? [String: Any] {
                let zones = object["zones"] as? [[String: Any]]
                let displayZone =
                    object["displayTz"] as? String ?? object["tz"] as? String
                    ?? zones?.first?["tz"] as? String ?? zone
                let from = object["from"] as? [String: Any]
                let to = object["to"] as? [String: Any]
                let legs = object["legs"] as? [[String: Any]]
                let lastArrival = legs?.last?["to"] as? [String: Any]
                return object.reduce(into: [String: Any]()) { result, entry in
                    let (key, value) = entry
                    let fieldZone: String
                    switch key {
                    case "markedAt":
                        result[key] = value
                        return
                    case "departureUtc", "departLocal": fieldZone = from?["zone"] as? String ?? displayZone
                    case "arrivalUtc", "arriveLocal": fieldZone = to?["zone"] as? String ?? displayZone
                    case "endUtc":
                        fieldZone = lastArrival?["zone"] as? String ?? zones?.last?["tz"] as? String ?? displayZone
                    case "arrivalLandingUtc", "assumedReturn": fieldZone = fixture.card.to.zone
                    default: fieldZone = displayZone
                    }
                    result[key] = transform(value, zone: fieldZone)
                }
            }
            if let array = value as? [Any] { return array.map { transform($0, zone: zone) } }
            guard let text = value as? String else { return value }
            var calendar = calendar
            calendar.timeZone = TimeZone(identifier: zone)!
            if text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z$"#, options: .regularExpression) != nil {
                return (calendar.date(byAdding: .day, value: days, to: instant(text))! + Double(minutes * 60))
                    .ISO8601Format()
            }
            guard text.range(of: #"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$"#, options: .regularExpression) != nil else {
                return text
            }
            dateFormatter.calendar = calendar
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.dateFormat = text.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
            if let date = dateFormatter.date(from: text),
                let shifted = calendar.date(byAdding: .day, value: days, to: date)
            {
                return dateFormatter.string(from: text.contains("T") ? shifted + Double(minutes * 60) : shifted)
            }
            return text
        }
        func move<Value: Codable>(_ value: Value) throws -> Value {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            let data = try JSONSerialization.data(withJSONObject: transform(object, zone: zone.identifier))
            return try JSONDecoder().decode(Value.self, from: data)
        }
        var card = try move(fixture.card)
        var detail = try move(fixture.detail)
        func local(_ utc: String, zone: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: zone)!
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            return formatter.string(from: instant(utc))
        }
        for day in detail.plan.days.indices {
            let value = detail.plan.days[day]
            detail.plan.days[day].labelDate = String(local(value.startUtc, zone: value.zones.first!.tz).prefix(10))
            if value.labelRange != nil {
                let last = String(
                    local((instant(value.endUtc) - 1).ISO8601Format(), zone: value.zones.last!.tz).prefix(10))
                detail.plan.days[day].labelRange = last > detail.plan.days[day].labelDate ? last : nil
            }
        }
        let airports = [card.from, card.to] + card.connections + detail.trip.legs.flatMap { [$0.from, $0.to] }
        for index in detail.plan.blocks.indices {
            let block = detail.plan.blocks[index]
            if block.checkKey != nil {
                detail.plan.blocks[index].checkKey?.localDate = String(
                    local(block.startUtc, zone: block.displayTz).prefix(10))
            }
            if case .zoneChange(var params) = block.params,
                let from = airports.first(where: { $0.iata == params.departureIata }),
                let to = airports.first(where: { $0.iata == params.arrivalIata })
            {
                let at = instant(block.startUtc)
                params.offsetMin =
                    (TimeZone(identifier: to.zone)!.secondsFromGMT(for: at)
                        - TimeZone(identifier: from.zone)!.secondsFromGMT(for: at)) / 60
                detail.plan.blocks[index].params = .zoneChange(params)
            }
        }
        for index in detail.checkState.marks.indices {
            let key = fixture.detail.checkState.marks[index].key
            if let blockIndex = fixture.detail.plan.blocks.firstIndex(where: { $0.checkKey == key }),
                let rebased = detail.plan.blocks[blockIndex].checkKey
            {
                detail.checkState.marks[index].key = rebased
            }
        }
        let hashInput = "\(fixture.detail.plan.meta.inputHash):\(days)" + (minutes == 0 ? "" : ":\(minutes)")
        let hash = SHA256.hash(data: Data(hashInput.utf8)).map { String(format: "%02x", $0) }.joined()
        detail.plan.meta.inputHash = hash
        detail.checkState.planInputHash = hash
        detail.detailVersion = "\(fixture.detail.detailVersion)-\(hash)"
        card.departLocal = local(card.departureUtc, zone: card.from.zone)
        card.arriveLocal = local(card.arrivalUtc, zone: card.to.zone)
        let departureOffset = TimeZone(identifier: card.from.zone)!.secondsFromGMT(for: instant(card.departureUtc))
        let arrivalOffset = TimeZone(identifier: card.to.zone)!.secondsFromGMT(for: instant(card.arrivalUtc))
        card.offsetDifferenceMinutes = (arrivalOffset - departureOffset) / 60
        detail.trip.departLocal = local(detail.trip.departureUtc, zone: detail.trip.from.zone)
        detail.trip.offsetDifferenceMin = card.offsetDifferenceMinutes
        for day in detail.timeline.days.indices {
            for tick in detail.timeline.days[day].ticks.indices {
                let value = detail.timeline.days[day].ticks[tick]
                detail.timeline.days[day].ticks[tick].offsetMin =
                    TimeZone(identifier: value.tz)!
                    .secondsFromGMT(for: instant(value.atUtc)) / 60
            }
        }
        return Template(card: card, detail: detail)
    }
}

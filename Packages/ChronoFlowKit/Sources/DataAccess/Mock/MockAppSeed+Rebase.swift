#if DEBUG
    import AppCore
    import CryptoKit
    import Foundation

    extension MockAppSeed {
        static func rebase(_ fixture: TripFixture, index: Int, now: Date) throws -> TripFixture {
            let utcFormatter = ISO8601DateFormatter()
            func instant(_ value: String) -> Date {
                let normalized = value.count == 17 ? value.replacingOccurrences(of: "Z", with: ":00Z") : value
                return utcFormatter.date(from: normalized)!
            }
            let zone = TimeZone(identifier: fixture.card.from.zone)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let source = index == 2 ? fixture.detail.plan.days.last!.endUtc : fixture.detail.plan.days.first!.startUtc
            let distance = index == 0 ? -1 : index == 2 ? -3 : 3 + index
            let target = calendar.date(byAdding: .day, value: distance, to: now)!
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: instant(source)), to: calendar.startOfDay(for: target)
            ).day!
            let shifted = calendar.date(byAdding: .day, value: days, to: instant(source))!
            let delta = shifted.timeIntervalSince(instant(source))
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.calendar = calendar
            dateFormatter.timeZone = zone
            dateFormatter.dateFormat = "yyyy-MM-dd"

            func transform(_ value: Any) -> Any {
                if let object = value as? [String: Any] {
                    return object.mapValues(transform)
                }
                if let array = value as? [Any] { return array.map(transform) }
                guard let text = value as? String else { return value }
                if text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?Z$"#, options: .regularExpression) != nil {
                    return (instant(text) + delta).ISO8601Format()
                }
                if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                    let date = dateFormatter.date(from: text),
                    let shifted = calendar.date(byAdding: .day, value: days, to: date)
                {
                    return dateFormatter.string(from: shifted)
                }
                return text
            }
            func move<Value: Codable>(_ value: Value) throws -> Value {
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
                let data = try JSONSerialization.data(withJSONObject: transform(object))
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
            let hashInput = "\(fixture.detail.plan.meta.inputHash):\(delta)"
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
            return TripFixture(card: card, detail: detail)
        }
    }
#endif

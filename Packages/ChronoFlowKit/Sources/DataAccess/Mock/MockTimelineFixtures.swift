import AppCore
import CryptoKit
import Foundation

public enum MockTimelineFixtures {
    public struct Fixture: Sendable {
        public var card: TripCardView
        public var detail: TripDetail
    }

    public static func fixture(named name: String) throws -> Fixture {
        let templates = try MockTripFixtures.templates()
        if name == "large30" || name == "large60" {
            return try large(days: name == "large30" ? 30 : 60, template: templates[2], caffeineTemplate: templates[0])
        }
        let index = name.hasPrefix("S") ? Int(name.dropFirst()).map { $0 - 1 } : nil
        guard
            let template = index.flatMap({ templates.indices.contains($0) ? templates[$0] : nil })
                ?? templates.first(where: { $0.card.id == name })
        else { throw DataFailure.server(status: 404) }
        return Fixture(card: template.card, detail: template.detail)
    }

    private static func large(
        days count: Int, template: MockTripFixtures.Template, caffeineTemplate: MockTripFixtures.Template
    ) throws -> Fixture {
        let source = template.detail
        let cycle = Array(source.plan.days.prefix(6))
        let start = instant(cycle[0].startUtc)
        let end = instant(cycle.last!.endUtc)
        let duration = end.timeIntervalSince(start)
        let sourceBlocks = source.plan.blocks.filter { instant($0.startUtc) < end && instant($0.endUtc) >= start }
        let sourceDayIDs = Set(cycle.map(\.id))
        let sourceBlockIDs = Set(sourceBlocks.map(\.id))
        var result = source
        result.plan.days = []
        result.plan.blocks = []
        result.timeline.days = []
        result.timeline.blockReasons = []
        result.timeline.transferWarnings = []
        result.notices.days = []
        result.checkState.days = []
        result.checkState.marks = []
        for index in 0..<(count / cycle.count) {
            let suffix = "-tour-\(index)"
            let shift = duration * Double(index)
            let clone = try shifted(source, by: shift, suffix: suffix, dayIDs: sourceDayIDs, blockIDs: sourceBlockIDs)
            result.plan.days += clone.plan.days.filter { sourceDayIDs.contains(String($0.id.dropLast(suffix.count))) }
            result.plan.blocks += clone.plan.blocks.filter {
                sourceBlockIDs.contains(String($0.id.dropLast(suffix.count)))
            }.map {
                var block = $0
                block.startUtc = max(instant(block.startUtc), start + shift).ISO8601Format()
                block.endUtc = min(instant(block.endUtc), end + shift).ISO8601Format()
                return block
            }
            result.timeline.days += clone.timeline.days.filter {
                sourceDayIDs.contains(String($0.dayId.dropLast(suffix.count)))
            }
            result.timeline.blockReasons += clone.timeline.blockReasons.filter {
                sourceBlockIDs.contains(String($0.blockId.dropLast(suffix.count)))
            }
            result.timeline.transferWarnings += clone.timeline.transferWarnings.filter {
                sourceBlockIDs.contains(String($0.blockId.dropLast(suffix.count)))
            }
            result.notices.days += clone.notices.days.filter {
                sourceDayIDs.contains(String($0.dayId.dropLast(suffix.count)))
            }
        }
        let caffeinePlan = caffeineTemplate.detail.plan
        let caffeineDay = caffeinePlan.days.first { day in
            day.phase == .post
                && caffeinePlan.blocks.filter {
                    $0.lane == .caffeine && instant($0.startUtc) >= instant(day.startUtc)
                        && instant($0.startUtc) < instant(day.endUtc)
                }.count >= 3
        }!
        let caffeine = caffeinePlan.blocks.filter {
            $0.lane == .caffeine && instant($0.startUtc) >= instant(caffeineDay.startUtc)
                && instant($0.startUtc) < instant(caffeineDay.endUtc)
        }
        for (index, day) in result.plan.days.enumerated() {
            let shift = instant(day.startUtc).timeIntervalSince(instant(caffeineDay.startUtc))
            let blocks = try shifted(
                caffeine, by: shift, suffix: "-caffeine-day-\(index)", dayIDs: [], blockIDs: Set(caffeine.map(\.id)))
            result.plan.blocks += blocks.map {
                var block = $0
                block.startUtc = min(instant(block.startUtc), instant(day.endUtc)).ISO8601Format()
                block.endUtc = min(instant(block.endUtc), instant(day.endUtc)).ISO8601Format()
                block.displayTz = day.zones.first!.tz
                return block
            }
        }
        let id = "0199a3c0-0000-7000-8000-0000000000\(count)"
        let hash = SHA256.hash(data: Data("timeline-\(count)-S3-prefix6-S1-caffeine-v2".utf8)).map {
            String(format: "%02x", $0)
        }
        .joined()
        result.trip.id = id
        result.trip.endUtc = result.plan.days.last!.endUtc
        result.plan.meta.inputHash = hash
        result.checkState.planInputHash = hash
        result.detailVersion = hash
        result.plan.meta.assumedReturn = nil
        var card = template.card
        card.id = id
        return Fixture(card: card, detail: result)
    }

    private static func shifted<Value: Codable>(
        _ detail: Value, by seconds: TimeInterval, suffix: String, dayIDs: Set<String>, blockIDs: Set<String>
    ) throws -> Value {
        func transform(_ value: Any) -> Any {
            if let array = value as? [Any] { return array.map(transform) }
            if let object = value as? [String: Any] { return object.mapValues(transform) }
            guard let string = value as? String else { return value }
            if dayIDs.contains(string) || blockIDs.contains(string) { return string + suffix }
            if string.count >= 17, string.contains("T"), string.hasSuffix("Z"), let date = parse(string) {
                return (date + seconds).ISO8601Format()
            }
            if string.count == 10, let date = parse(string + "T12:00:00Z") {
                return String((date + seconds).ISO8601Format().prefix(10))
            }
            return string
        }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(detail))
        let data = try JSONSerialization.data(withJSONObject: transform(object))
        return try JSONDecoder().decode(Value.self, from: data)
    }
    private static func parse(_ string: String) -> Date? {
        ISO8601DateFormatter().date(
            from: string.count == 17 ? string.replacingOccurrences(of: "Z", with: ":00Z") : string)
    }
    private static func instant(_ string: String) -> Date { parse(string)! }
}

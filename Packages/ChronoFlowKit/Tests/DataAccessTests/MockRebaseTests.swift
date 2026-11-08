import AppCore
import Foundation
import Testing

@testable import DataAccess

#if DEBUG
    @Suite struct MockRebaseTests {
        @Test(arguments: ["2026-10-25T12:00:00Z", "2026-11-01T12:00:00Z", "2026-11-07T12:00:00Z"])
        func preservesWallTimesAcrossAmsterdamAndNewYorkDST(nowText: String) throws {
            let originals = try JSONDecoder().decode(MockAppSeed.Fixtures.self, from: MockTripFixtures.fixtureData())
            let now = MockAppSeed.instant(nowText)
            var changedOffsets: Set<String> = []
            func expectWallTime(_ old: String, _ new: String, zone: String) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: zone)!
                let before = MockAppSeed.instant(old)
                let after = MockAppSeed.instant(new)
                #expect(
                    calendar.dateComponents([.hour, .minute, .second], from: before)
                        == calendar.dateComponents([.hour, .minute, .second], from: after))
                if calendar.timeZone.secondsFromGMT(for: before) != calendar.timeZone.secondsFromGMT(for: after) {
                    changedOffsets.insert(zone)
                }
            }
            func expectCopyInstants(_ old: Any, _ new: Any) {
                if let before = old as? [String: Any], let after = new as? [String: Any] {
                    if before["kind"] as? String == "instant", let zone = before["tz"] as? String,
                        let oldValue = before["value"] as? String, let newValue = after["value"] as? String
                    {
                        expectWallTime(oldValue, newValue, zone: zone)
                    }
                    for (key, value) in before {
                        if let next = after[key] { expectCopyInstants(value, next) }
                    }
                } else if let before = old as? [Any], let after = new as? [Any] {
                    for (before, after) in zip(before, after) { expectCopyInstants(before, after) }
                }
            }
            for (index, old) in originals.trips.enumerated() {
                let new = try MockAppSeed.rebase(old, index: index, now: now)
                expectCopyInstants(
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode(old.detail)),
                    try JSONSerialization.jsonObject(with: JSONEncoder().encode(new.detail)))
                expectWallTime(old.card.departureUtc, new.card.departureUtc, zone: old.card.from.zone)
                expectWallTime(old.card.arrivalUtc, new.card.arrivalUtc, zone: old.card.to.zone)
                #expect(old.card.departLocal.suffix(5) == new.card.departLocal.suffix(5))
                #expect(old.card.arriveLocal.suffix(5) == new.card.arriveLocal.suffix(5))
                expectWallTime(
                    old.detail.trip.endUtc, new.detail.trip.endUtc,
                    zone: old.detail.trip.legs.last!.to.zone)
                if let before = old.detail.plan.meta.arrivalLandingUtc,
                    let after = new.detail.plan.meta.arrivalLandingUtc
                {
                    expectWallTime(before, after, zone: old.card.to.zone)
                }
                if let before = old.detail.plan.meta.assumedReturn, let after = new.detail.plan.meta.assumedReturn {
                    expectWallTime(before.leaveUtc, after.leaveUtc, zone: old.card.to.zone)
                }
                for (before, after) in zip(old.detail.plan.days, new.detail.plan.days) {
                    expectWallTime(before.startUtc, after.startUtc, zone: before.zones.first!.tz)
                    expectWallTime(before.endUtc, after.endUtc, zone: before.zones.last!.tz)
                    for (before, after) in zip(before.zones, after.zones) {
                        expectWallTime(before.startUtc, after.startUtc, zone: before.tz)
                        expectWallTime(before.endUtc, after.endUtc, zone: before.tz)
                    }
                }
                for (before, after) in zip(old.detail.plan.blocks, new.detail.plan.blocks) {
                    expectWallTime(before.startUtc, after.startUtc, zone: before.displayTz)
                    expectWallTime(before.endUtc, after.endUtc, zone: before.displayTz)
                    if case .caffeineRoutine(let oldParams) = before.params,
                        case .caffeineRoutine(let newParams) = after.params,
                        let oldLast = oldParams.lastByUtc, let newLast = newParams.lastByUtc
                    {
                        expectWallTime(oldLast, newLast, zone: before.displayTz)
                    }
                }
                for (before, after) in zip(
                    old.detail.timeline.days.flatMap(\.ticks), new.detail.timeline.days.flatMap(\.ticks))
                {
                    expectWallTime(before.atUtc, after.atUtc, zone: before.tz)
                }
            }
            #expect(changedOffsets.contains("Europe/Amsterdam"))
            if nowText != "2026-10-25T12:00:00Z" {
                #expect(changedOffsets.contains("America/New_York"))
            }
        }
    }
#endif

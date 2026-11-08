#if DEBUG
    import AppCore
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
            return try MockTripFixtures.rebase(fixture, days: days)
        }
    }
#endif

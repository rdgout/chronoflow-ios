import AppCore
import Foundation
import LocalStore
import PlanCore
import Testing

@testable import PlanUI

extension ModelTests {
    @Test @MainActor func tripsSectionsKeepRNNewestFirstAndStableTies() throws {
        let detail = try detail()
        let card = recoveryCard(detail)
        func value(_ id: String, _ status: TripStatus, _ departure: String) -> TripListValue {
            var card = card
            card.id = id
            card.departureUtc = departure
            return TripListValue(card: card, planStartUtc: nil, planEndUtc: nil, status: status)
        }
        let sections = tripSections([
            value("b", .upcoming, "2026-11-10T00:00:00Z"), value("a", .upcoming, "2026-11-10T00:00:00Z"),
            value("new", .upcoming, "2026-11-11T00:00:00Z"), value("active", .active, "2026-11-01T00:00:00Z"),
            value("past", .completed, "2026-10-01T00:00:00Z"),
        ])
        #expect(sections.map(\.status) == [.active, .upcoming, .completed])
        #expect(sections[1].trips.map(\.card.id) == ["new", "b", "a"])
        #expect(tripSections([]).isEmpty)
    }
    @Test @MainActor func tombstonedTripsDisappearAndEmptyFirstLoadFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000016")
        let repository = TripRepository(database: db)
        let detail = try detail()
        let now = planDate(detail.plan.days[0].startUtc)
        let model = TripsModel(repository: repository, clock: TestPlanClock(now), now: now)
        model.start()
        defer { model.stop() }
        try await eventually { model.hasLoaded }
        #expect(model.trips.isEmpty)
        var record = TripRecord(
            id: detail.trip.id, card: try .encoding(recoveryCard(detail)),
            departureUtc: detail.trip.departureUtc)
        try await repository.upsert(record)
        try await eventually { model.trips.count == 1 }
        record.deletedLocally = true
        try await repository.upsert(record)
        try await eventually { model.trips.isEmpty }
        record.deletedLocally = false
        record.deletedAt = now.ISO8601Format()
        try await repository.upsert(record)
        #expect(await PlanDecoder().trips([record], now: now).values.isEmpty)
        model.stop()
        try await db.close()
    }
}

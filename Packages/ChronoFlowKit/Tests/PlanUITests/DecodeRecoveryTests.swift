import AppCore
import Foundation
import LocalStore
import PlanCore
import Testing

@testable import PlanUI

extension ModelTests {
    @Test @MainActor func detailDecodeFailureRecoversAndKeepsObserving() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000016")
        let repository = TripRepository(database: db)
        var value = try detail()
        let card = recoveryCard(value)
        let date = planDate(value.plan.days[0].startUtc)
        var trip = TripRecord(
            id: card.id, card: try .encoding(card), currentInputHash: value.plan.meta.inputHash,
            departureUtc: card.departureUtc)
        try await repository.upsert(trip)
        var plan = PlanVersionRecord(
            tripId: trip.id, inputHash: value.plan.meta.inputHash, detail: try JSONDocument("{}"),
            receivedAt: date.ISO8601Format(), detailVersion: value.detailVersion)
        try await repository.store(plan: plan, checks: [])
        let decoder = PlanDecoder()
        let model = TripPlanModel(
            tripID: trip.id, repository: repository, clock: TestPlanClock(date), decoder: decoder, now: date)
        model.start()
        defer { model.stop() }
        try await eventually { model.error != nil }
        #expect(model.detail == nil)

        plan.detail = try .encoding(value)
        try await repository.store(plan: plan, checks: [])
        try await eventually { model.detail == value && !model.layouts.isEmpty && model.error == nil }
        #expect(await decoder.decodeCount == 1)

        plan.detail = try JSONDocument("{}")
        try await repository.store(plan: plan, checks: [])
        try await eventually { model.error != nil }
        value.plan.meta.inputHash = "recovered-hash"
        plan.inputHash = value.plan.meta.inputHash
        plan.detail = try .encoding(value)
        try await repository.store(plan: plan, checks: [])
        trip.currentInputHash = plan.inputHash
        try await repository.upsert(trip)
        try await eventually { model.detail == value && model.error == nil }
        #expect(await decoder.decodeCount == 2)

        try await db.write { try $0.execute(sql: "DELETE FROM plan_versions") }
        try await eventually { model.detail == nil && model.layouts.isEmpty && model.error == nil }
        try await repository.store(plan: plan, checks: [])
        try await eventually { model.detail == value && model.error == nil }
        #expect(await decoder.decodeCount == 3)
        #expect(await decoder.decodedOnMainThread == false)
        model.stop()
        try await db.close()
    }

    @Test @MainActor func badCardIsSkippedWhileOtherTripsKeepUpdating() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000017")
        let repository = TripRepository(database: db)
        let value = try detail()
        var card = recoveryCard(value)
        var healthy = TripRecord(id: card.id, card: try .encoding(card), departureUtc: card.departureUtc)
        var bad = TripRecord(
            id: "00000000-0000-4000-8000-000000000001", card: try JSONDocument("{}"),
            departureUtc: card.departureUtc)
        try await repository.upsert(bad)
        try await repository.upsert(healthy)
        let date = planDate(value.plan.days[0].startUtc)
        let model = TripsModel(repository: repository, clock: TestPlanClock(date), now: date)
        model.start()
        defer { model.stop() }
        try await eventually { model.error != nil && model.trips.map(\.card.id) == [card.id] }

        card.canEdit = true
        healthy.card = try .encoding(card)
        try await repository.upsert(healthy)
        try await eventually { model.trips.first?.card == card }
        #expect(model.error != nil)

        var repaired = card
        repaired.id = bad.id
        bad.card = try .encoding(repaired)
        try await repository.upsert(bad)
        try await eventually { model.trips.count == 2 && model.error == nil }
        #expect(Set(model.trips.map(\.card.id)) == [card.id, repaired.id])

        card.canDelete = true
        healthy.card = try .encoding(card)
        try await repository.upsert(healthy)
        try await eventually { model.trips.first { $0.card.id == card.id }?.card == card }
        #expect(model.error == nil)

        bad.card = try JSONDocument("{}")
        try await repository.upsert(bad)
        try await eventually { model.trips.map(\.card.id) == [card.id] && model.error != nil }
        try await repository.remove(id: bad.id)
        try await eventually { model.trips.map(\.card.id) == [card.id] && model.error == nil }
        model.stop()
        try await db.close()
    }

    private func recoveryCard(_ value: TripDetail) -> TripCardView {
        TripCardView(
            id: value.trip.id, from: value.trip.from, to: value.trip.to, departLocal: value.trip.departLocal,
            arriveLocal: "", departureUtc: value.trip.departureUtc, arrivalUtc: value.trip.endUtc, connections: [],
            offsetDifferenceMinutes: 0, progress: .init(status: .upcoming), canComplete: false, canReopen: false,
            canEdit: false, canDuplicate: false, canDelete: false)
    }
}

import Foundation
import LocalStore
import PlanCore
import Testing

@testable import AppCore
@testable import PlanUI

extension ModelTests {
    @Test @MainActor func localCheckUndoAndReplanAreObservedThroughTheOutbox() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000016")
        try await AccountRepository(database: db).upsert(
            AccountRecord(
                id: "00000000-0000-4000-8000-000000000016", name: "Test", email: "test@example.com"))
        var value = try detail()
        let block = try #require(value.plan.blocks.first { $0.actionable && $0.checkKey != nil })
        let date = planDate(block.startUtc)
        let repository = TripRepository(database: db)
        var trip = TripRecord(
            id: value.trip.id, card: try .encoding(recoveryCard(value)),
            currentInputHash: value.plan.meta.inputHash, departureUtc: value.trip.departureUtc)
        try await repository.upsert(trip)
        var plan = PlanVersionRecord(
            tripId: trip.id, inputHash: value.plan.meta.inputHash,
            detail: try .encoding(value), receivedAt: date.ISO8601Format())
        try await repository.store(plan: plan, checks: [])
        let permit = SessionMutationPermit()
        let model = TripPlanModel(
            tripID: trip.id, repository: repository, clock: TestPlanClock(date), now: date, mutationPermit: permit)
        model.start()
        defer { model.stop() }
        try await eventually { model.detail != nil }
        try await model.setCheck(blockID: block.id, status: .done)
        try await eventually { model.detail?.checkState.marks.first?.status == .done }
        #expect(try await OutboxRepository(database: db).pending().count == 1)
        value.plan.meta.inputHash = "replacement"
        plan.inputHash = "replacement"
        plan.detail = try .encoding(value)
        try await repository.store(plan: plan, checks: [])
        trip.currentInputHash = "replacement"
        try await repository.upsert(trip)
        try await eventually { model.detail?.plan.meta.inputHash == "replacement" }
        #expect(model.detail?.checkState.marks.first?.status == .done)
        try await model.setCheck(blockID: block.id, status: nil)
        try await eventually { model.detail?.checkState.marks.isEmpty == true }
        let pending = try await OutboxRepository(database: db).pending()
        permit.invalidate()
        await #expect(throws: CancellationError.self) {
            try await model.setCheck(blockID: block.id, status: .skipped)
        }
        #expect(try await OutboxRepository(database: db).pending().count == pending.count)
        #expect(model.detail?.checkState.marks.isEmpty == true)
        model.stop()
        try await model.setCheck(blockID: block.id, status: .done)
        #expect(try await OutboxRepository(database: db).pending().count == pending.count)
        model.start()
        value.plan.blocks.removeAll()
        plan.detail = try .encoding(value)
        try await repository.store(plan: plan, checks: [])
        try await eventually { model.detail?.plan.blocks.isEmpty == true }
        model.stop()
        try await db.close()
    }

    @Test func localProgressCountsStartsAndKeepsSkippedSeparate() throws {
        let value = try detail()
        let blocks = value.plan.blocks.filter { $0.actionable && $0.checkKey != nil }
        let marks = Array(blocks.prefix(2).enumerated()).map { index, block in
            CheckMark(key: block.checkKey!, status: index == 0 ? .done : .skipped, markedAt: block.startUtc)
        }
        let state = buildCheckState(value.plan, marks: marks)
        #expect(state.marks.count == marks.count)
        #expect(state.days.reduce(0) { $0 + $1.done } == min(1, marks.count))
        #expect(state.days.reduce(0) { $0 + $1.skipped } == max(0, marks.count - 1))
    }
}

import AppCore
import Foundation
import LocalStore
import PlanCore
import Testing

@testable import PlanUI

actor TestPlanClock: PlanClock {
    private var continuations: [UUID: AsyncStream<Date>.Continuation] = [:]
    private var current: Date
    init(_ date: Date) { current = date }
    func values() -> AsyncStream<Date> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Date>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.yield(current)
        continuation.onTermination = { _ in Task { await self.remove(id) } }
        return stream
    }
    func remove(_ id: UUID) { continuations[id] = nil }
    func advance(_ date: Date) {
        current = date
        for c in continuations.values { c.yield(date) }
    }
}

struct ModelTests {
    func detail() throws -> TripDetail {
        try JSONDecoder().decode(
            TripDetail.self,
            from: Data(
                contentsOf: Bundle.module.url(forResource: "detail", withExtension: "json", subdirectory: "Fixtures")!))
    }

    @MainActor func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }

    @Test @MainActor func observationCacheEvictionClockAndHashReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000014")
        let repository = TripRepository(database: db)
        let value = try detail()
        let card = TripCardView(
            id: value.trip.id, from: value.trip.from, to: value.trip.to, departLocal: value.trip.departLocal,
            arriveLocal: "", departureUtc: value.trip.departureUtc, arrivalUtc: value.trip.endUtc, connections: [],
            offsetDifferenceMinutes: 0, progress: .init(status: .upcoming), canComplete: false, canReopen: false,
            canEdit: false, canDuplicate: false, canDelete: false)
        let day = value.plan.days[0]
        let date = planDate(value.plan.days[0].startUtc)
        var trip = TripRecord(
            id: value.trip.id, card: try .encoding(card), currentInputHash: value.plan.meta.inputHash,
            departureUtc: card.departureUtc, planStartUtc: day.startUtc, planEndUtc: day.endUtc)
        try await repository.upsert(trip)
        let plan = PlanVersionRecord(
            tripId: trip.id, inputHash: value.plan.meta.inputHash, detail: try .encoding(value),
            receivedAt: date.ISO8601Format(), detailVersion: value.detailVersion)
        try await repository.store(plan: plan, checks: [])
        let clock = TestPlanClock(date)
        let decoder = PlanDecoder()
        let model = TripPlanModel(tripID: trip.id, repository: repository, clock: clock, decoder: decoder, now: date)
        let trips = TripsModel(repository: repository, clock: clock, decoder: decoder, now: date)
        model.start()
        model.start()
        trips.start()
        defer {
            model.stop()
            trips.stop()
        }
        try await eventually { model.detail != nil && !model.layouts.isEmpty && trips.trips.count == 1 }
        #expect(trips.trips[0].status == .active)
        #expect(model.nowOffsets[day.id] == 0)
        #expect(await decoder.decodeCount == 1)
        #expect(await decoder.decodedOnMainThread == false)
        _ = try await decoder.detail(plan)
        #expect(await decoder.decodeCount == 1)
        await clock.advance(date.addingTimeInterval(60))
        try await eventually { model.now == date.addingTimeInterval(60) }
        #expect(abs((model.nowOffsets[day.id] ?? -1) - PlanMetrics.pointsPerMinute) < 1e-8)
        await clock.advance(planDate(day.endUtc))
        try await eventually { trips.trips[0].status == .completed }
        model.hiddenCategories = [.sleep]
        try await eventually {
            model.layouts.values.allSatisfy { $0.placed[.sleep]!.allSatisfy { $0.block.type != .sleep } }
        }
        #expect(model.layouts.values.allSatisfy { $0.placed[.sleep]!.allSatisfy { $0.block.type != .sleep } })
        try await db.write { try $0.execute(sql: "DELETE FROM plan_versions") }
        try await eventually { model.detail == nil && model.layouts.isEmpty }
        try await repository.store(plan: plan, checks: [])
        try await eventually { model.detail != nil }
        #expect(await decoder.decodeCount == 2)
        var updated = value
        updated.plan.meta.inputHash = "replacement"
        updated.detailVersion = "replacement-version"
        let replacement = PlanVersionRecord(
            tripId: trip.id, inputHash: "replacement", detail: try .encoding(updated), receivedAt: date.ISO8601Format(),
            detailVersion: updated.detailVersion)
        try await repository.store(plan: replacement, checks: [])
        trip.currentInputHash = "replacement"
        try await repository.upsert(trip)
        try await eventually { model.detail?.plan.meta.inputHash == "replacement" }
        #expect(await decoder.decodeCount == 3)
        try await repository.remove(id: trip.id)
        try await eventually { model.detail == nil && trips.trips.isEmpty }
        model.stop()
        trips.stop()
        try await db.close()
    }

    @Test @MainActor func stopReleasesModelAndRestartObserves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000015")
        let clock = TestPlanClock(Date(timeIntervalSince1970: 0))
        var model: TripsModel? = TripsModel(repository: .init(database: db), clock: clock)
        weak let weakModel = model
        model?.start()
        try await eventually { model?.now == Date(timeIntervalSince1970: 0) }
        model?.stop()
        model?.start()
        await clock.advance(Date(timeIntervalSince1970: 60))
        try await eventually { model?.now == Date(timeIntervalSince1970: 60) }
        model = nil
        try await eventually { weakModel == nil }
        try await db.close()
    }

    @Test func versionAndRawPayloadInvalidateCache() async throws {
        let decoder = PlanDecoder()
        var value = try detail()
        var record = PlanVersionRecord(
            tripId: value.trip.id, inputHash: value.plan.meta.inputHash,
            detail: try .encoding(value), receivedAt: "now", detailVersion: value.detailVersion)
        _ = try await decoder.detail(record)
        _ = try await decoder.detail(record)
        #expect(await decoder.decodeCount == 1)
        value.detailVersion = "new-version"
        record.detailVersion = value.detailVersion
        record.detail = try .encoding(value)
        #expect(try await decoder.detail(record).detailVersion == "new-version")
        #expect(await decoder.decodeCount == 2)
        value.plan.blocks.removeAll()
        record.detail = try .encoding(value)
        #expect(try await decoder.detail(record).plan.blocks.isEmpty)
        #expect(await decoder.decodeCount == 3)
        #expect(await decoder.decodedOnMainThread == false)
    }

    @Test func systemClockRefreshesForTimeZoneNotification() async throws {
        let stream = await SystemPlanClock().values()
        var iterator = stream.makeAsyncIterator()
        let first = try #require(await iterator.next())
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        let next = try #require(await iterator.next())
        #expect(next >= first)
    }
}

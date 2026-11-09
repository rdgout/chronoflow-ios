import AppCore
import DataAccess
import Foundation
import LocalStore
import Observation
import PlanCore
import SwiftUI
import Sync
import Testing

@testable import PlanUI

struct TimelineInvalidationTests {
    @Test @MainActor func scrollingAndTicksInvalidateOnlyAffectedClockChildren() async throws {
        let fixture = try MockTimelineFixtures.fixture(named: "large60")
        let detail = fixture.detail
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: "00000000-0000-4000-8000-000000000017")
        let repository = TripRepository(database: database)
        try await repository.upsert(
            TripRecord(
                id: detail.trip.id, card: .encoding(fixture.card), currentInputHash: detail.plan.meta.inputHash,
                departureUtc: fixture.card.departureUtc))
        try await repository.store(
            plan: PlanVersionRecord(
                tripId: detail.trip.id, inputHash: detail.plan.meta.inputHash, detail: .encoding(detail),
                receivedAt: detail.trip.departureUtc, detailVersion: detail.detailVersion), checks: [])
        let first = detail.plan.days[0]
        let start = planDate(first.startUtc)
        let clock = TestPlanClock(start)
        let model = TripPageModel(
            tripID: detail.trip.id, repository: repository, retention: PlanRetention(), path: nil, clock: clock,
            now: start)
        model.start()
        defer { model.stop() }
        try await ModelTests().eventually { model.plan.prepared?.days.count == 60 && !model.plan.nowTexts.isEmpty }
        model.acceptPreparedPlan()
        let prepared = try #require(model.plan.prepared)
        let renderer = TimelineRenderer()
        let symbols = TimelineSymbols()

        for timeline in [true, false] {
            func row(_ day: PreparedDay) -> TripDayRow {
                TripDayRow(
                    day: day, layout: model.plan.layouts[day.id], clock: model.plan.dayClock(for: day.id),
                    timeline: timeline, copy: PageCopy(language: .en), renderer: renderer, symbols: symbols,
                    viewportHeight: PlanMetrics.skeletonTimeline, onBlock: { _ in }, onFrame: {})
            }
            let rows = prepared.days.map(row)
            func observe() -> InvalidationProbe {
                let probe = InvalidationProbe()
                for row in rows {
                    let id = row.day.id
                    withObservationTracking {
                        _ = row.body
                    } onChange: {
                        probe.record("static", id)
                    }
                    withObservationTracking {
                        _ = row.clockContent.body
                    } onChange: {
                        probe.record("clock", id)
                    }
                }
                return probe
            }
            await clock.advance(start)
            try await ModelTests().eventually { model.plan.dayClock(for: first.id).now == start }
            let scrolling = observe()
            let control = InvalidationProbe()
            withObservationTracking {
                _ = model.anchor
            } onChange: {
                control.record("anchor", first.id)
            }
            let tracker = TripScrollTracker()
            for offset in 1...120 {
                tracker.frames = ["header." + first.id: CGRect(x: 0, y: -offset, width: 0, height: 0)]
                tracker.updateChrome(dayID: first.id, reduceMotion: false)
                model.select(dayID: first.id, offset: Double(offset))
            }
            model.select(dayID: prepared.days[1].id)
            #expect(control.ids("anchor") == [first.id])
            #expect(scrolling.ids("static").isEmpty)
            #expect(scrolling.ids("clock").isEmpty)
            #expect(zip(rows, prepared.days.map(row)).allSatisfy { $0 == $1 })

            let ticking = observe()
            await clock.advance(start + 60)
            try await ModelTests().eventually { model.plan.dayClock(for: first.id).now == start + 60 }
            #expect(ticking.ids("static").isEmpty)
            #expect(ticking.ids("clock") == [first.id])

            let boundary = observe()
            let next = prepared.days[1].day
            await clock.advance(planDate(next.startUtc))
            try await ModelTests().eventually {
                model.plan.dayClock(for: next.id).now == planDate(next.startUtc)
                    && model.plan.dayClock(for: first.id).now == .distantPast
            }
            #expect(boundary.ids("static").isEmpty)
            #expect(boundary.ids("clock") == [first.id, next.id])
        }
        model.stop()
        try await database.close()
    }
}

private nonisolated final class InvalidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var changes: [String: Set<String>] = [:]
    func record(_ kind: String, _ id: String) { lock.withLock { _ = changes[kind, default: []].insert(id) } }
    func ids(_ kind: String) -> Set<String> { lock.withLock { changes[kind] ?? [] } }
}

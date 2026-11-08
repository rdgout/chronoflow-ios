import AppCore
import DataAccess
import DesignSystem
import Foundation
import LocalStore
import Observation
import PlanCore
import Sync
import Testing

@testable import PlanUI

struct TimelineRenderingTests {
    @Test func vectorDrawingsStayWithinTraversalBudgetAndInvalidateCorrectly() async throws {
        let detail = try MockTimelineFixtures.fixture(named: "large60").detail
        let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let prepared = preparePlan(detail, layouts: layouts, formatter: formatter, language: .en)
        let renderer = TimelineRenderer()
        var largest = 0
        for width in [358.0, 637.0] {
            for day in prepared.days {
                let layout = try #require(layouts[day.id])
                let drawing = try await renderer.render(
                    day: day, layout: layout, width: width, scale: 3,
                    fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:])
                #expect(drawing.document.numberOfPages == 1)
                #expect(abs(drawing.page.getBoxRect(.mediaBox).height - layout.height) < 0.001)
                #expect(drawing.dividerFrames.count == layout.dividers.count)
                largest = max(largest, drawing.byteCount)
                #expect(drawing.byteCount < 512 * 1_024)
                #expect(await renderer.cachedBytes <= TimelineRenderer.cacheByteLimit)
            }
        }
        let day = try #require(prepared.days.last)
        let layout = try #require(layouts[day.id])
        let count = await renderer.renderCount
        let cached = try await renderer.render(
            day: day, layout: layout, width: 637, scale: 3,
            fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:])
        let repeated = try await renderer.render(
            day: day, layout: layout, width: 637, scale: 3,
            fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:])
        #expect(cached.document === repeated.document)
        #expect(await renderer.renderCount == count)
        _ = try await renderer.render(
            day: day, layout: layout, width: 637, scale: 3,
            fontSize: PlanMetrics.laneLabelSize, appearance: .dark, symbols: [:])
        #expect(await renderer.renderCount == count + 1)
        print("Timeline vectors: largest \(largest) bytes across 60 days at phone and Duo widths")
    }

    @Test @MainActor func scrollingOffsetsDoNotInvalidateTheObservableAnchor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000017")
        let repo = TripRepository(database: db)
        let fixture = try MockTimelineFixtures.fixture(named: "S3")
        let detail = fixture.detail
        try await repo.upsert(
            TripRecord(
                id: detail.trip.id, card: try .encoding(fixture.card),
                currentInputHash: detail.plan.meta.inputHash, departureUtc: detail.trip.departureUtc))
        try await repo.store(
            plan: PlanVersionRecord(
                tripId: detail.trip.id, inputHash: detail.plan.meta.inputHash,
                detail: try .encoding(detail), receivedAt: detail.trip.departureUtc, detailVersion: detail.detailVersion
            ), checks: [])
        let model = TripPageModel(
            tripID: detail.trip.id, repository: repo, retention: PlanRetention(),
            dayID: detail.plan.days[0].id, awaitingSync: true, path: nil)
        model.start()
        defer { model.stop() }
        try await ModelTests().eventually { model.plan.prepared != nil }
        #expect(!model.awaitingSync)
        model.acceptPreparedPlan()
        let probe = AnchorInvalidations()
        withObservationTracking {
            _ = model.anchor
        } onChange: {
            probe.record()
        }
        for offset in 0..<10_000 { model.select(dayID: detail.plan.days[0].id, offset: Double(offset)) }
        #expect(probe.count == 0)
        #expect(model.currentAnchor.offset == 9_999)
        model.select(dayID: detail.plan.days[1].id)
        #expect(probe.count == 1)
        model.stop()
        try await db.close()
    }

    @Test func accessibilityTargetsFollowTilesAndGutterMarkers() async throws {
        let detail = try MockTimelineFixtures.fixture(named: "S3").detail
        let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let prepared = preparePlan(detail, layouts: layouts, formatter: formatter, language: .nl)
        for width in [288.0, 358.0, 637.0] {
            for day in prepared.days {
                let layout = try #require(layouts[day.id])
                let geometry = TimelineGeometry(layout: layout, availableWidth: width)
                for block in day.blocks {
                    let target = try #require(timelineBlockFrame(block.id, geometry: geometry, layout: layout))
                    #expect(target.height >= PlanMetrics.touch)
                    #expect(target.minX >= 0 && target.maxX <= geometry.width)
                    #expect(target.minY >= 0 && target.maxY <= geometry.height)
                    if let tile = geometry.tiles.first(where: { $0.blockID == block.id }) {
                        #expect(target == tile.hitFrame)
                    }
                }
            }
        }
    }
}

private final class AnchorInvalidations: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func record() { lock.withLock { value += 1 } }
}

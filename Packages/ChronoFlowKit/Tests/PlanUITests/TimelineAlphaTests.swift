import CoreGraphics
import DataAccess
import DesignSystem
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct TimelineAlphaTests {
    @Test func coreBarDoesNotFadeTheTitleOrInterval() async throws {
        let detail = try MockTimelineFixtures.fixture(named: "S3").detail
        let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
        let prepared = preparePlan(
            detail, layouts: layouts,
            formatter: CopyLineFormatter(catalog: try await CopyCatalog.load()), language: .en)
        var day = try #require(
            prepared.days.first { day in
                layouts[day.id]?.placed[.sleep]?.contains(where: { $0.block.type == .sleep }) == true
            })
        var layout = try #require(layouts[day.id])
        var placed = try #require(layout.placed[.sleep]?.first { $0.block.type == .sleep })
        var block = try #require(day.blocks.first { $0.id == placed.block.id })
        placed.top = 40
        placed.height = 120
        placed.cols = 2
        placed.col = 0
        placed.tiny = false
        placed.continuesBefore = false
        placed.continuesAfter = false
        layout.height = 200
        layout.markers = []
        layout.changes = []
        layout.dividers = []
        layout.ticks = []
        block.status = nil
        day.blocks = [block]
        day.ticks = []
        day.dividerLabels = []
        layout.placed = [.sleep: [placed], .light: [], .caffeine: [], .travel: []]
        let renderer = TimelineRenderer()
        func variant(core: Bool) async throws -> [UInt8] {
            var variant = day
            var variantLayout = layout
            variant.blocks[0].block.priority = core ? .core : .recommended
            variantLayout.placed[.sleep]?[0].block.priority = core ? .core : .recommended
            let drawing = try await renderer.render(
                day: variant, layout: variantLayout, width: 358, scale: 3,
                fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:])
            return try pixels(drawing, width: 358, height: 200)
        }
        let core = try await variant(core: true)
        let recommended = try await variant(core: false)
        let frame = try #require(TimelineGeometry(layout: layout, availableWidth: 358).tiles.first?.frame)
        var differencesOutsideBar = 0
        for y in 0..<200 {
            for x in 0..<358 where Double(x) < frame.minX - 1 || Double(x) > frame.minX + PlanMetrics.coreBorder + 1 {
                let index = (y * 358 + x) * 4
                if core[index..<index + 4] != recommended[index..<index + 4] { differencesOutsideBar += 1 }
            }
        }
        #expect(differencesOutsideBar == 0)
        #expect(core != recommended)
    }
}

private func pixels(_ drawing: TimelineDrawing, width: Int, height: Int) throws -> [UInt8] {
    var data = [UInt8](repeating: 0, count: width * height * 4)
    try data.withUnsafeMutableBytes { buffer in
        let context = try #require(
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.drawPDFPage(drawing.page)
    }
    return data
}

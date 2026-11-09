import CoreGraphics
import DataAccess
import DesignSystem
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct TimelineAlphaTests {
    @Test func compactAndTinyTilesHideAllCopyAndInvalidateTheCache() async throws {
        let detail = try MockTimelineFixtures.fixture(named: "S3").detail
        let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
        let prepared = preparePlan(
            detail, layouts: layouts,
            formatter: CopyLineFormatter(catalog: try await CopyCatalog.load()), language: .en)
        var day = try #require(prepared.days.first)
        var layout = try #require(layouts[day.id])
        var placed = try #require(layout.placed[.sleep]?.first)
        var block = try #require(day.blocks.first { $0.id == placed.block.id })
        placed.top = 0
        placed.height = 120
        placed.cols = 1
        placed.col = 0
        placed.tiny = false
        placed.continuesBefore = false
        placed.continuesAfter = false
        block.status = nil
        day.blocks = [block]
        day.ticks = []
        day.dividerLabels = []
        layout.height = placed.height
        layout.markers = []
        layout.changes = []
        layout.dividers = []
        layout.ticks = []
        layout.placed = [.sleep: [placed], .light: [], .caffeine: [], .travel: []]
        var changed = day
        changed.blocks[0].title = "Changed title"
        changed.blocks[0].interval = "00:00 – 23:59"
        changed.blocks[0].priority = "Changed priority"
        changed.blocks[0].reason = "Changed reason"
        let renderer = TimelineRenderer()
        for appearance in [TokenAppearance.light, .dark] {
            for windowWidth in [320.0, 390, 393, 430, 639, 640, 669] {
                let width = windowWidth - PlanMetrics.gutter * 2
                let compact = windowWidth < PlanMetrics.timelineLabelBreakpoint
                func render(_ value: PreparedDay, compact: Bool) async throws -> TimelineDrawing {
                    try await renderer.render(
                        day: value, layout: layout, width: width, scale: 3,
                        fontSize: PlanMetrics.laneLabelSize, appearance: appearance, symbols: [:], compact: compact)
                }
                let original = try await render(day, compact: compact)
                let copyChanged = try await render(changed, compact: compact)
                let originalPixels = try pixels(original, width: Int(width), height: 120)
                let changedPixels = try pixels(copyChanged, width: Int(width), height: 120)
                #expect((originalPixels == changedPixels) == compact)
                let repeated = try await render(changed, compact: compact)
                #expect(repeated.document === copyChanged.document)
                let toggled = try await render(changed, compact: !compact)
                #expect(toggled.document !== copyChanged.document)
                #expect(try pixels(toggled, width: Int(width), height: 120) != changedPixels)
            }
        }
        layout.placed[.sleep]?[0].tiny = true
        let original = try await renderer.render(
            day: day, layout: layout, width: 637, scale: 3,
            fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:], compact: false)
        let copyChanged = try await renderer.render(
            day: changed, layout: layout, width: 637, scale: 3,
            fontSize: PlanMetrics.laneLabelSize, appearance: .light, symbols: [:], compact: false)
        #expect(try pixels(original, width: 637, height: 120) == pixels(copyChanged, width: 637, height: 120))
        #expect(day.blocks[0].accessibilityLabel.contains(day.blocks[0].title))
        #expect(day.blocks[0].accessibilityLabel.contains(day.blocks[0].interval))
    }

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

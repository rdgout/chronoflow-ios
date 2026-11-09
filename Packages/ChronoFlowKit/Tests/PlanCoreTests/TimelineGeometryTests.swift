import AppCore
import Foundation
import SnapshotSupport
import Testing

@testable import PlanCore

struct TimelineGeometryTests {
    @Test func bucketedLayoutMatchesFullScan() throws {
        for name in ["S1", "S2", "S3", "S4", "S5", "S6", "S6-RETURN-10N"] {
            var value = try fixture(name)
            value.plan.days.reverse()
            value.plan.blocks.reverse()
            let index = indexTimeline(value.timeline)
            for hidden: [BlockType] in [[], [.sleep, .zoneChange]] {
                let fast = layoutPlan(value.plan, timeline: value.timeline, hidden: hidden)
                for day in value.plan.days {
                    #expect(
                        fast[day.id]
                            == layoutDay(day, blocks: value.plan.blocks, presentation: index, hidden: Set(hidden)))
                }
            }
        }
    }

    @Test func allScenarioDaysFitDeviceWidths() throws {
        for name in ["S1", "S2", "S3", "S4", "S5", "S6", "S6-RETURN-10N"] {
            let fixture = try fixture(name)
            for layout in layoutPlan(fixture.plan, timeline: fixture.timeline).values {
                for device in try SnapshotDevice.all() {
                    let width = Double(device.width - device.insets.left - device.insets.right) - PlanMetrics.gutter * 2
                    let geometry = TimelineGeometry(layout: layout, availableWidth: width)
                    #expect(geometry.height == layout.height)
                    #expect(geometry.width >= width && geometry.width >= layout.minWidth)
                    #expect(geometry.laneWidth >= PlanMetrics.minColumnWidth)
                    for tile in geometry.tiles {
                        #expect(tile.frame.width > 0 && tile.frame.height > 0)
                        #expect(tile.frame.minX >= PlanMetrics.gutterWidth && tile.frame.maxX <= geometry.width)
                        #expect(tile.frame.minY >= 0 && tile.frame.maxY <= geometry.height + 0.001)
                        #expect(tile.hitFrame.width >= PlanMetrics.touch && tile.hitFrame.height >= PlanMetrics.touch)
                        #expect(tile.hitFrame.minX >= 0 && tile.hitFrame.maxX <= geometry.width)
                    }
                }
            }
        }
    }
}

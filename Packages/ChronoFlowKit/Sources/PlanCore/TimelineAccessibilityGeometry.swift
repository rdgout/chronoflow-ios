import Foundation

public func timelineBlockFrame(_ blockID: String, geometry: TimelineGeometry, layout: DayLayout) -> CGRect? {
    if let tile = geometry.tiles.first(where: { $0.blockID == blockID }) { return tile.hitFrame }
    if let marker = layout.markers.first(where: { $0.block.id == blockID }) {
        return CGRect(
            x: 0, y: max(0, min(marker.top - PlanMetrics.touch / 2, geometry.height - PlanMetrics.touch)),
            width: PlanMetrics.gutterWidth, height: PlanMetrics.touch)
    }
    if let change = layout.changes.first(where: { $0.block.id == blockID }) {
        return CGRect(
            x: PlanMetrics.gutterWidth + PlanMetrics.laneGap,
            y: max(0, min(change.top - PlanMetrics.touch / 2, geometry.height - PlanMetrics.touch)),
            width: geometry.width - PlanMetrics.gutterWidth - PlanMetrics.laneGap, height: PlanMetrics.touch)
    }
    return nil
}

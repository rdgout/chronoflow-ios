import AppCore
import Foundation

public struct TimelineTileFrame: Sendable, Equatable {
    public var blockID: String
    public var frame: CGRect
    public var hitFrame: CGRect
    public var tiny: Bool
    public var continuesBefore: Bool
    public var continuesAfter: Bool
}

public struct TimelineGeometry: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public var laneWidth: Double
    public var tiles: [TimelineTileFrame]

    public init(layout: DayLayout, availableWidth: Double) {
        width = max(layout.minWidth, availableWidth)
        height = layout.height
        laneWidth = (width - PlanMetrics.gutterWidth) / Double(timelineLanes.count) - PlanMetrics.laneGap
        let width = width
        let height = height
        let laneWidth = laneWidth
        tiles = timelineLanes.enumerated().flatMap { index, lane in
            (layout.placed[lane] ?? []).map { placed in
                let column = laneWidth / Double(placed.cols)
                let x =
                    PlanMetrics.gutterWidth + PlanMetrics.laneGap + Double(index) * (laneWidth + PlanMetrics.laneGap)
                    + Double(placed.col) * column + PlanMetrics.tileInset
                let frame = CGRect(
                    x: x, y: placed.top, width: max(0, column - PlanMetrics.tileInset * 2), height: placed.height)
                let targetWidth = max(PlanMetrics.gutterWidth, frame.width)
                let targetHeight = max(PlanMetrics.gutterWidth, frame.height)
                return TimelineTileFrame(
                    blockID: placed.block.id, frame: frame,
                    hitFrame: CGRect(
                        x: max(0, min(x - (targetWidth - frame.width) / 2, width - targetWidth)),
                        y: max(0, min(placed.top - (targetHeight - frame.height) / 2, height - targetHeight)),
                        width: targetWidth, height: targetHeight), tiny: placed.tiny,
                    continuesBefore: placed.continuesBefore, continuesAfter: placed.continuesAfter)
            }
        }
    }
}

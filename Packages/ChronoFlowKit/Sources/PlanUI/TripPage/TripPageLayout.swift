import Foundation
import PlanCore

public nonisolated struct TripPageLayout: Equatable, Sendable {
    public let listWidth: Double?
    public var isWide: Bool { listWidth != nil }
    public var gutter: Double { isWide ? PlanMetrics.wideGutter : PlanMetrics.gutter }

    // Width only: the unfolded Duo held flat is landscape (951 pt) and is the widest case, not a phone.
    public static func resolve(width: Double) -> Self {
        guard width >= PlanMetrics.wideBreakpoint else { return Self(listWidth: nil) }
        return Self(
            listWidth: width >= PlanMetrics.wideLargeBreakpoint
                ? PlanMetrics.wideLargeListWidth : PlanMetrics.wideListWidth)
    }
}

nonisolated struct TripWideListPosition: Equatable, Sendable {
    let offset: Double
    let height: Double

    init(dayTop: Double, dayHeight: Double, viewportHeight: Double, stickyTop: Double, contentHeight: Double) {
        offset = min(max(0, stickyTop - dayTop), max(0, dayHeight))
        height = max(
            0,
            min(
                dayHeight - offset, viewportHeight - stickyTop,
                PlanMetrics.wideListMaxHeight, contentHeight))
    }
}

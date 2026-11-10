import Foundation
import PlanCore

public nonisolated struct TripPageLayout: Equatable, Sendable {
    public let listWidth: Double?
    public var isWide: Bool { listWidth != nil }
    public var gutter: Double { isWide ? PlanMetrics.wideGutter : PlanMetrics.gutter }

    public static func resolve(width: Double, height: Double) -> Self {
        guard width >= PlanMetrics.wideBreakpoint, height > width else { return Self(listWidth: nil) }
        return Self(
            listWidth: width >= PlanMetrics.wideLargeBreakpoint
                ? PlanMetrics.wideLargeListWidth : PlanMetrics.wideListWidth)
    }
}

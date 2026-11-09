import Foundation

public struct FixedPlanClock: PlanClock {
    public let now: Date

    public init(now: Date) { self.now = now }

    public func values() async -> AsyncStream<Date> {
        AsyncStream {
            $0.yield(now)
            $0.finish()
        }
    }
}

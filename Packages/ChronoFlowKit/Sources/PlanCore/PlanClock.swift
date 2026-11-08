import Foundation

public protocol PlanClock: Sendable {
    func values() async -> AsyncStream<Date>
}

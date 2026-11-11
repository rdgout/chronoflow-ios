public struct LockoutWait: Sendable, Equatable {
    public enum Unit: Sendable { case seconds, minutes, hours }
    public let unit: Unit
    public let count: Int

    public init(seconds: Int) {
        let seconds = max(0, seconds)
        let divisor: Int
        if seconds >= 3600 {
            unit = .hours
            divisor = 3600
        } else if seconds >= 60 {
            unit = .minutes
            divisor = 60
        } else {
            unit = .seconds
            divisor = 1
        }
        count = seconds / divisor + (seconds % divisor > 0 ? 1 : 0)
    }

    public var localizationKey: String {
        switch unit {
        case .seconds: "Too many attempts. Try again in %lld seconds."
        case .minutes: "Too many attempts. Try again in %lld minutes."
        case .hours: "Too many attempts. Try again in %lld hours."
        }
    }
}

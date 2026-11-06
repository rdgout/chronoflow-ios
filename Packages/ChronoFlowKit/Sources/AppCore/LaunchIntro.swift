import Foundation

@MainActor
public final class LaunchIntro {
    public let start: Duration
    public let clock: any LaunchClock
    public let frozenTime: Duration?
    public private(set) var hasPlayed = false

    public init(start: Duration, clock: any LaunchClock, frozenTime: Duration? = nil) {
        self.start = start
        self.clock = clock
        self.frozenTime = frozenTime
    }

    public func claim() -> Bool {
        guard !hasPlayed else { return false }
        hasPlayed = true
        return true
    }

    nonisolated public static func offset(for index: Int) -> Duration {
        precondition((0..<6).contains(index))
        return .milliseconds([0, 100, 150, 300, 400, 450][index])
    }

    public func progress(for index: Int, at time: Duration) -> Double {
        let elapsed = (time - start - Self.offset(for: index)).secondsValue
        return CubicBezier.intro.value(at: min(1, max(0, elapsed / 0.45)))
    }

    public func delay(for index: Int) -> Double { (start + Self.offset(for: index) - clock.now).secondsValue }
}

extension Duration {
    fileprivate var secondsValue: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

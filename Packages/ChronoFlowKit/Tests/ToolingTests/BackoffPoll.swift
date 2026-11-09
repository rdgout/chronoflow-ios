import Foundation

nonisolated enum BackoffPoll {
    static func until(
        timeout: TimeInterval,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        condition: () -> Bool
    ) -> Bool {
        let deadline = now() + max(0, timeout)
        var interval = 0.05
        if condition() { return true }
        while now() < deadline {
            pause(min(interval, deadline - now()))
            guard now() < deadline else { return false }
            if condition() { return true }
            interval = min(1, interval * 1.5)
        }
        return false
    }
}

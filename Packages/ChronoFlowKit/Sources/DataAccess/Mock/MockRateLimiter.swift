import AppCore
import Foundation

enum MockRateLimiter {
    struct Window: Codable, Sendable, Equatable {
        var count: Int
        let expiresAt: TimeInterval
    }
    static func hit(
        _ key: String, limit: Int = 5, seconds: TimeInterval = 60, now: TimeInterval, windows: inout [String: Window]
    ) throws {
        let window =
            windows[key].flatMap { $0.expiresAt > now ? $0 : nil } ?? Window(count: 0, expiresAt: now + seconds)
        guard window.count < limit else {
            throw DataFailure.throttled(retryAfterSeconds: max(0, window.expiresAt - now), status: 429)
        }
        windows[key] = Window(count: window.count + 1, expiresAt: window.expiresAt)
    }
}

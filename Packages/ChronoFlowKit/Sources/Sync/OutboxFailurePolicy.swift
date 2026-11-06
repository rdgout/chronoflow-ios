import AppCore
import Foundation

public enum OutboxFailurePolicy {
    public static func isFinal(_ error: DataFailure) -> Bool {
        if case .emailUnverified = error { return false }
        guard let status = error.status else { return false }
        return (400..<500).contains(status) && ![401, 408, 425, 429].contains(status)
    }

    public static func sanitized(_ error: DataFailure) -> String {
        switch error {
        case .offline: "offline"
        case .unauthorized: "unauthorized"
        case .emailUnverified: "email_unverified"
        case .validation: "validation"
        case .throttled: "throttled"
        case .conflict: "conflict"
        case .server: "server"
        case .unsupported: "unsupported"
        }
    }

    public static func retryDelay(attempts: Int, retryAfter: TimeInterval = 0) -> TimeInterval {
        max(min(pow(2, Double(max(0, min(attempts, 9)))), 300), retryAfter)
    }
}

public struct SyncRefusal: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let status: Int?
    public let failedAt: String
    public let lastError: String
}

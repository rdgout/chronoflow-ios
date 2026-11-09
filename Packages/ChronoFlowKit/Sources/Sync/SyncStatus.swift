import AppCore
import Foundation

public enum SyncState: Sendable, Equatable {
    case idle, offline, verificationRequired, unauthorized, failed
}

public struct SyncResult: Sendable, Equatable {
    public let state: SyncState
    public let pendingCount: Int
    public let retryAfter: TimeInterval?
    public let serverRetryAfter: TimeInterval?
    public let refusals: [SyncRefusal]
    public init(
        state: SyncState, pendingCount: Int, retryAfter: TimeInterval? = nil, serverRetryAfter: TimeInterval? = nil,
        refusals: [SyncRefusal] = []
    ) {
        self.state = state
        self.pendingCount = pendingCount
        self.retryAfter = retryAfter
        self.serverRetryAfter = serverRetryAfter
        self.refusals = refusals
    }
}

public enum SyncEvent: Sendable, Equatable {
    case started(accountID: AccountID, epoch: UInt64)
    case finished(accountID: AccountID, epoch: UInt64, result: SyncResult)
}

public struct SyncScheduler: Sendable {
    public let now: @Sendable () -> Date
    public let sleep: @Sendable (TimeInterval) async throws -> Void
    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.now = now
        self.sleep = sleep
    }
}

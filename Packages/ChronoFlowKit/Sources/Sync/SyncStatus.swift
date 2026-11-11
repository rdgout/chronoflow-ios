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
    public let changes: SyncChanges
    public init(
        state: SyncState, pendingCount: Int, retryAfter: TimeInterval? = nil, serverRetryAfter: TimeInterval? = nil,
        refusals: [SyncRefusal] = [], changes: SyncChanges = SyncChanges()
    ) {
        self.state = state
        self.pendingCount = pendingCount
        self.retryAfter = retryAfter
        self.serverRetryAfter = serverRetryAfter
        self.refusals = refusals
        self.changes = changes
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

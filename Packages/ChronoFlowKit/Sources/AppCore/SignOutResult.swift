import Foundation

public enum SignOutResult: Sendable, Equatable {
    case signedOut
    case needsConfirmation(pendingCount: Int)
}

public struct SessionTeardown: Sendable {
    public var prepare: @Sendable () async throws -> Void = {}
    public var pendingCount: @Sendable () async throws -> Int = { 0 }
    public var flush: @Sendable () async throws -> Void = {}
    public var beginWipe: @Sendable (AccountID) async throws -> Void = { _ in }
    public var erase: @Sendable (AccountID) async throws -> Void = { _ in }
    public var finishWipe: @Sendable () async throws -> Void = {}
    public var logout: @Sendable (StoredSession) async throws -> Void = { _ in }
    public var detach: @Sendable () async -> Void = {}
    public var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    public init() {}
}

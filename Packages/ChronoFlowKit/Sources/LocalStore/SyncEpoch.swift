import AppCore
import Foundation
import GRDB

public final class SyncEpoch: Sendable {
    public let accountID: AccountID
    public let generation: UInt64
    private let state = NSLock()
    nonisolated(unsafe) private var valid = true
    private let parent: SyncEpoch?

    public init(accountID: AccountID, generation: UInt64) {
        self.accountID = accountID
        self.generation = generation
        parent = nil
    }

    private init(parent: SyncEpoch) {
        accountID = parent.accountID
        generation = parent.generation
        self.parent = parent
    }

    public func child() -> SyncEpoch { SyncEpoch(parent: self) }

    public func invalidate() { state.withLock { valid = false } }

    public func check() throws {
        try Task.checkCancellation()
        try whileValid {}
    }

    // Hold validity through SQLite's commit so detach cannot race response application.
    func whileValid<T>(_ operation: () throws -> T) throws -> T {
        if let parent { return try parent.whileValid { try ownValidity(operation) } }
        return try ownValidity(operation)
    }

    private func ownValidity<T>(_ operation: () throws -> T) throws -> T {
        try state.withLock {
            guard valid else { throw CancellationError() }
            return try operation()
        }
    }
}

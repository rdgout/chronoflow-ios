import AppCore
import Foundation
import GRDB

public final class SyncEpoch: Sendable {
    public let accountID: AccountID
    public let generation: UInt64
    private let state = NSLock()
    nonisolated(unsafe) private var valid = true

    public init(accountID: AccountID, generation: UInt64) {
        self.accountID = accountID
        self.generation = generation
    }

    public func invalidate() { state.withLock { valid = false } }

    public func check() throws {
        try Task.checkCancellation()
        try whileValid {}
    }

    // Hold validity through SQLite's commit so detach cannot race response application.
    func whileValid<T>(_ operation: () throws -> T) throws -> T {
        try state.withLock {
            guard valid else { throw CancellationError() }
            return try operation()
        }
    }
}

import Foundation

public final class SessionMutationPermit: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var valid = true

    init() {}

    func invalidate() { lock.withLock { valid = false } }

    // Publication waits for an admitted SQLite transaction to commit before revoking the session.
    public func whileValid<T>(_ operation: () throws -> T) throws -> T {
        try lock.withLock {
            guard valid else { throw CancellationError() }
            return try operation()
        }
    }
}

import Foundation
import GRDB

final class ObservationLifetime<Value: Sendable>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let continuation: AsyncThrowingStream<Value, any Error>.Continuation
    private var cancellable: AnyDatabaseCancellable?
    private var stopped = false

    init(_ continuation: AsyncThrowingStream<Value, any Error>.Continuation) { self.continuation = continuation }

    func install(_ cancellable: AnyDatabaseCancellable) {
        lock.lock()
        if stopped {
            lock.unlock()
            cancellable.cancel()
        } else {
            self.cancellable = cancellable
            lock.unlock()
        }
    }

    func yield(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        if !stopped { continuation.yield(value) }
    }

    func fail(_ error: any Error) {
        cancel(error: error)
    }

    func cancel() { cancel(error: nil) }

    private func cancel(error: (any Error)?) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let cancellable = self.cancellable
        self.cancellable = nil
        lock.unlock()
        cancellable?.cancel()
        continuation.finish(throwing: error)
    }
}

import Foundation

actor TestGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var didArrive = false
    func block() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            didArrive = true
            for arrival in arrivals { arrival.resume() }
            arrivals.removeAll()
        }
    }
    func waitUntilBlocked() async {
        if didArrive { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func release() {
        blocked?.resume()
        blocked = nil
    }
}

actor ManualSyncScheduler {
    private var sleeps: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedDelays: [Double] = []
    func sleep(_ delay: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleeps[id] = continuation
                requestedDelays.append(delay)
                for arrival in arrivals { arrival.resume() }
                arrivals.removeAll()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        try Task.checkCancellation()
    }
    private func cancel(_ id: UUID) { sleeps.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
    func waitForSleep() async {
        if !sleeps.isEmpty { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func advance() {
        let pending = sleeps
        sleeps.removeAll()
        for c in pending.values { c.resume() }
    }
    var pendingCount: Int { sleeps.count }
}

final class WriteBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var didEnter = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    func block() {
        lock.withLock {
            didEnter = true
            for arrival in arrivals { arrival.resume() }
            arrivals.removeAll()
        }
        semaphore.wait()
    }
    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if didEnter { continuation.resume() } else { arrivals.append(continuation) }
            }
        }
    }
    func release() { semaphore.signal() }
}

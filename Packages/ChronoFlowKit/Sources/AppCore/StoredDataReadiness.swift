import Foundation

public struct StoredAccountReadiness: Sendable, Equatable {
    public let accountID: String
    public let gate: Gate
    public let hasStoredData: Bool
    public init(accountID: String, gate: Gate, hasStoredData: Bool) {
        self.accountID = accountID
        self.gate = gate
        self.hasStoredData = hasStoredData
    }
}

public actor StoredDataReadiness: LaunchReadiness {
    public typealias Values = AsyncThrowingStream<StoredAccountReadiness?, any Error>
    private let controller: SessionController
    private let values: @Sendable (String) async throws -> Values
    private let retrySignal = ReadinessRetrySignal()
    private var restoration: Task<SessionPresence, Never>?
    public private(set) var failure: SessionFailure?
    public private(set) var firstLoadEpoch: UInt64?

    public init(controller: SessionController, values: @escaping @Sendable (String) async throws -> Values) {
        self.controller = controller
        self.values = values
    }

    public func session() async -> SessionPresence {
        if restoration?.isCancelled == true { restoration = nil }
        if restoration == nil { restoration = Task { await self.restore() } }
        let task = restoration!
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func restore() async -> SessionPresence {
        while !Task.isCancelled {
            let revision = await retrySignal.revision
            do {
                let session = try await controller.restore()
                try Task.checkCancellation()
                failure = nil
                return session
            } catch is CancellationError { break } catch {
                failure = (error as? SessionFailure) ?? .databaseUnavailable
                do { try await retrySignal.wait(after: revision) } catch { break }
            }
        }
        return .signedOut
    }

    public func retry() async { await retrySignal.signal() }

    public func gate() async -> Gate { await firstValue()?.gate ?? .app }
    public func hasStoredData() async -> Bool { await firstValue()?.hasStoredData ?? false }

    private func firstValue() async -> StoredAccountReadiness? {
        var iterator = updates().makeAsyncIterator()
        return await iterator.next() ?? nil
    }

    private func updates() -> AsyncStream<StoredAccountReadiness?> {
        let (stream, continuation) = AsyncStream<StoredAccountReadiness?>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let task = Task { await self.forward(continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func forward(_ continuation: AsyncStream<StoredAccountReadiness?>.Continuation) async {
        defer { continuation.finish() }
        guard case .signedIn(let id) = await controller.presence else {
            continuation.yield(nil)
            return
        }
        let epoch = await controller.epoch
        while !Task.isCancelled {
            let revision = await retrySignal.revision
            do {
                let stream = try await values(id)
                for try await value in stream {
                    guard !Task.isCancelled, await controller.epoch == epoch else { return }
                    guard value == nil || value?.accountID == id else { throw SessionFailure.databaseUnavailable }
                    failure = nil
                    continuation.yield(value)
                }
                return
            } catch is CancellationError { return } catch {
                guard await controller.epoch == epoch else { return }
                failure = .databaseUnavailable
                do { try await retrySignal.wait(after: revision) } catch { return }
            }
        }
    }

    public func gateUpdates() async -> AsyncStream<Gate> {
        let (stream, continuation) = AsyncStream<Gate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let source = updates()
        let task = Task {
            for await value in source {
                guard !Task.isCancelled else { break }
                continuation.yield(value?.gate ?? .app)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // Match the async requirement so the protocol's one-shot default cannot shadow this stream.
    public func storedDataUpdates() async -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let source = updates()
        let task = Task {
            for await value in source {
                guard !Task.isCancelled else { break }
                continuation.yield(value?.hasStoredData ?? false)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func allowFirstLoad() async {
        guard case .signedIn = await controller.presence else { return }
        firstLoadEpoch = await controller.epoch
    }
}

private actor ReadinessRetrySignal {
    private(set) var revision: UInt64 = 0
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    func wait(after revision: UInt64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard self.revision == revision else { return }
            try await withCheckedThrowingContinuation { waiters[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    func signal() {
        revision &+= 1
        let pending = waiters
        waiters.removeAll()
        for waiter in pending.values { waiter.resume() }
    }
    private func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

public struct SignedOutReadiness: LaunchReadiness {
    public init() {}
    public func session() -> SessionPresence { .signedOut }
    public func gate() -> Gate { .app }
    public func hasStoredData() -> Bool { true }
    public func allowFirstLoad() {}
}

public struct UnavailableReadiness: LaunchReadiness {
    public init() {}
    public func session() async -> SessionPresence {
        let values = AsyncStream<SessionPresence> { _ in }
        var iterator = values.makeAsyncIterator()
        return await iterator.next() ?? .signedOut
    }
    public func gate() -> Gate { .app }
    public func hasStoredData() -> Bool { false }
    public func allowFirstLoad() {}
}

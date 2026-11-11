import AppCore
import Foundation

public struct WizardCheckingClock: Sendable {
    public var now: @Sendable () -> TimeInterval
    public var sleepUntil: @Sendable (TimeInterval) async throws -> Void
    public init(
        now: @escaping @Sendable () -> TimeInterval,
        sleepUntil: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.now = now
        self.sleepUntil = sleepUntil
    }
    public static var continuous: Self {
        Self(
            now: { ProcessInfo.processInfo.systemUptime },
            sleepUntil: { deadline in
                try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
            })
    }
}

public struct WizardCheckingProgress: Sendable, Equatable {
    public var ticks = 0
    public var slow = false
    public var failure: DataFailure?
    public var retryAt: TimeInterval?
    public init() {}
    public func retrySeconds(at now: TimeInterval) -> Int { Int(ceil(max(0, (retryAt ?? now) - now))) }
}

public enum WizardChecking {
    public enum Event: Sendable {
        case tick(Int)
        case slow
        case complete(TripGenerationReviewResult)
        case failed(DataFailure)
    }

    public static func run(
        clock: WizardCheckingClock, request: @escaping @Sendable () async throws -> TripGenerationReviewResult,
        receive: @escaping @MainActor @Sendable (Event) -> Void
    ) async {
        let start = clock.now()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    let response = try await request()
                    try await clock.sleepUntil(start + 1.2)
                    try Task.checkCancellation()
                    await receive(.tick(3))
                    try await clock.sleepUntil(clock.now() + 0.3)
                    try Task.checkCancellation()
                    await receive(.complete(response))
                } catch is CancellationError {} catch {
                    guard !Task.isCancelled else { return }
                    await receive(.failed((error as? DataFailure) ?? .server(status: nil)))
                }
            }
            group.addTask {
                do {
                    for (time, event) in [(0.4, Event.tick(1)), (0.8, .tick(2)), (10, .slow)] {
                        try await clock.sleepUntil(start + time)
                        try Task.checkCancellation()
                        await receive(event)
                    }
                    try await clock.sleepUntil(start + 30)
                    try Task.checkCancellation()
                    await receive(.failed(.server(status: nil)))
                } catch {}
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}

import Foundation

#if canImport(QuartzCore)
    import QuartzCore
#endif

@MainActor
public protocol LaunchClock: AnyObject, Sendable {
    var now: Duration { get }
    func sleep(until deadline: Duration) async throws
}

@MainActor
public final class MediaLaunchClock: LaunchClock {
    public let t0: TimeInterval

    public init(t0: TimeInterval) { self.t0 = t0 }

    public var now: Duration {
        #if canImport(QuartzCore)
            .seconds(max(0, CACurrentMediaTime() - t0))
        #else
            .seconds(max(0, ProcessInfo.processInfo.systemUptime - t0))
        #endif
    }

    public func sleep(until deadline: Duration) async throws {
        let remaining = deadline - now
        if remaining > .zero { try await Task.sleep(for: remaining) }
        try Task.checkCancellation()
    }
}

@MainActor
public final class ManualLaunchClock: LaunchClock {
    public private(set) var now: Duration = .zero
    private var sleepers: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]
    public var pendingSleeps: Int { sleepers.count }

    public init() {}

    public func advance(to time: Duration) {
        precondition(time >= now)
        now = time
        let due = sleepers.filter { $0.value.0 <= time }
        for (id, sleeper) in due {
            sleepers.removeValue(forKey: id)
            sleeper.1.resume()
        }
    }

    public func sleep(until deadline: Duration) async throws {
        try Task.checkCancellation()
        guard deadline > now else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = (deadline, continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
        try Task.checkCancellation()
    }
}

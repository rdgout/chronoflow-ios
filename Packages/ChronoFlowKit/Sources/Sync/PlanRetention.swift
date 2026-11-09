import Foundation

public final class PlanRetention: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var leases: [UUID: String] = [:]
    public init() {}

    public func hold(tripID: String) -> PlanLease {
        let id = UUID()
        lock.withLock { leases[id] = tripID }
        return PlanLease { [weak self] in self?.release(id) }
    }
    func clear() { lock.withLock { leases.removeAll() } }
    private func release(_ id: UUID) { _ = lock.withLock { leases.removeValue(forKey: id) } }
    func withHeldPlans<T>(_ action: (Set<String>) throws -> T) rethrows -> T {
        try lock.withLock { try action(Set(leases.values)) }
    }
}

public final class PlanLease: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var releaseAction: (@Sendable () -> Void)?
    fileprivate init(release: @escaping @Sendable () -> Void) { releaseAction = release }
    public func release() {
        let action = lock.withLock {
            let action = releaseAction
            releaseAction = nil
            return action
        }
        action?()
    }
    deinit { releaseAction?() }
}

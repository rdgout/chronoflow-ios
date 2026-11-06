import Foundation

@MainActor
public final class LaunchCoordinator {
    public private(set) var state: LaunchState
    public let clock: any LaunchClock
    private let reduceMotion: Bool
    private let readiness: any LaunchReadiness
    private let onChange: @MainActor (LaunchState, [LaunchEffect]) -> Void
    private var tasks: [Task<Void, Never>] = []
    private var deadlineTask: Task<Void, Never>?
    private var started = false
    private var stopped = false

    public init(
        readiness: any LaunchReadiness, clock: any LaunchClock, reduceMotion: Bool,
        state: LaunchState = .init(), onChange: @escaping @MainActor (LaunchState, [LaunchEffect]) -> Void
    ) {
        self.readiness = readiness
        self.clock = clock
        self.reduceMotion = reduceMotion
        self.state = state
        self.onChange = onChange
    }

    public func start() {
        guard !started && !stopped else { return }
        started = true
        tasks.append(
            Task { [weak self, readiness] in
                let session = await readiness.session()
                guard let self, !Task.isCancelled, !stopped, !state.didForceReady else { return }
                send(.session(session))
                if case .signedIn = session {
                    tasks.append(
                        Task { [weak self, readiness] in
                            for await gate in await readiness.gateUpdates() {
                                guard !Task.isCancelled else { return }
                                self?.send(.gate(gate))
                            }
                        })
                    tasks.append(
                        Task { [weak self, readiness] in
                            for await stored in await readiness.storedDataUpdates() {
                                guard !Task.isCancelled else { return }
                                self?.send(.storedData(stored))
                            }
                        })
                }
            })
        for deadline in [Duration.seconds(2), .seconds(8)] {
            tasks.append(
                Task { [weak self, clock] in
                    do { try await clock.sleep(until: deadline) } catch { return }
                    self?.send(.reached(clock.now))
                })
        }
    }

    public func send(_ event: LaunchEvent) {
        guard !stopped else { return }
        let previous = state
        var effects = reduce(&state, .reached(clock.now), reduceMotion: reduceMotion)
        effects += reduce(&state, event, reduceMotion: reduceMotion)
        if previous != state || !effects.isEmpty { onChange(state, effects) }
        if effects.contains(.forceReady) {
            tasks.append(Task { [readiness] in await readiness.allowFirstLoad() })
        }
        if previous.welcomeDeadline != state.welcomeDeadline, let deadline = state.welcomeDeadline,
            !state.didCommitExit
        {
            deadlineTask?.cancel()
            deadlineTask = Task { [weak self, clock] in
                do { try await clock.sleep(until: deadline) } catch { return }
                self?.send(.reached(clock.now))
            }
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        deadlineTask?.cancel()
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    deinit {
        deadlineTask?.cancel()
        for task in tasks { task.cancel() }
    }
}

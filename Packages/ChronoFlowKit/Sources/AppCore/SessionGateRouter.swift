import Foundation

@MainActor public final class SessionGateRouter {
    private let controller: SessionController
    private let readiness: StoredDataReadiness
    private weak var navigator: (any Navigator)?
    private let verification: @MainActor (UInt64) async -> Void
    private var sessionTask: Task<Void, Never>?
    private var gateTask: Task<Void, Never>?

    public init(
        controller: SessionController, readiness: StoredDataReadiness, navigator: any Navigator,
        verification: @escaping @MainActor (UInt64) async -> Void
    ) {
        self.controller = controller
        self.readiness = readiness
        self.navigator = navigator
        self.verification = verification
    }

    public func start() {
        guard sessionTask == nil else { return }
        sessionTask = Task { [weak self, controller] in
            var sawSignedIn = false
            for await update in await controller.updates() {
                guard !Task.isCancelled, let self else { return }
                gateTask?.cancel()
                gateTask = nil
                if update.presence == .signedOut {
                    if sawSignedIn, await controller.epoch == update.epoch, !Task.isCancelled {
                        navigator?.navigate(to: .signIn)
                    }
                    continue
                }
                sawSignedIn = true
                guard case .signedIn = update.presence,
                    let snapshot = await controller.activeSession(), snapshot.epoch == update.epoch,
                    !Task.isCancelled
                else { continue }
                gateTask = Task { [weak self, readiness, controller, verification] in
                    var previous: Gate?
                    for await gate in await readiness.gateUpdates() {
                        guard !Task.isCancelled, await controller.activeSession() == snapshot,
                            !Task.isCancelled, let self
                        else { return }
                        guard gate != previous else { continue }
                        previous = gate
                        if gate == .verify {
                            await verification(snapshot.epoch)
                        } else {
                            navigator?.navigate(to: gate.route)
                        }
                    }
                }
            }
        }
    }

    public func stop() {
        sessionTask?.cancel()
        gateTask?.cancel()
        sessionTask = nil
        gateTask = nil
    }

    deinit {
        sessionTask?.cancel()
        gateTask?.cancel()
    }
}

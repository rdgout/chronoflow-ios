import AppCore
import Foundation
import LocalStore
import Observation
import PlanCore
import PlanUI
import Sync

@MainActor @Observable public final class SettingsHomeModel {
    public let refusedChanges = RefusedChangeModel()
    public private(set) var state: SettingsHomeState
    public private(set) var now: Date
    public private(set) var busy = false
    public var showsPending = false
    public private(set) var confirmationCount = 0
    public private(set) var syncing = false
    public private(set) var offline = false
    public private(set) var failure: (any Error)?
    @ObservationIgnored private let database: AccountDatabase?
    @ObservationIgnored private let controller: SessionController?
    @ObservationIgnored private var session: SessionSnapshot?
    @ObservationIgnored private let sync: SessionSync?
    @ObservationIgnored private let clock: any PlanClock
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = true

    public init(
        state: SettingsHomeState = SettingsHomeState(), database: AccountDatabase? = nil,
        controller: SessionController? = nil, session: SessionSnapshot? = nil, sync: SessionSync? = nil,
        clock: any PlanClock = SystemPlanClock(), now: Date = Date()
    ) {
        self.state = state
        confirmationCount = state.pending.count
        self.database = database
        self.controller = controller
        self.session = session
        self.sync = sync
        self.clock = clock
        self.now = now
    }

    public func start() {
        guard active, tasks.isEmpty, let database else { return }
        tasks = [
            Task { [weak self] in
                do {
                    for try await value in try await AccountRepository(database: database).values() {
                        guard !Task.isCancelled else { return }
                        self?.state.account = value
                    }
                } catch {}
            },
            Task { [weak self] in
                do {
                    for try await value in try await SettingsRepository(database: database).values() {
                        guard !Task.isCancelled else { return }
                        self?.state.apply(settings: value)
                    }
                } catch {}
            },
            Task { [weak self] in
                do {
                    for try await value in try await OutboxRepository(database: database).values() {
                        guard !Task.isCancelled else { return }
                        self?.receive(outbox: value)
                    }
                } catch {}
            },
            Task { [weak self, clock] in
                for await date in await clock.values() {
                    guard !Task.isCancelled else { return }
                    self?.now = date
                }
            },
        ]
        if let controller, let session {
            tasks.append(
                Task { [weak self] in
                    for await update in await controller.updates() {
                        guard !Task.isCancelled else { return }
                        guard update.epoch == session.epoch,
                            update.presence == .signedIn(accountID: session.session.accountId)
                        else {
                            self?.stop()
                            return
                        }
                    }
                })
        }
        if let sync, let session {
            tasks.append(
                Task { [weak self] in
                    for await event in await sync.events() {
                        guard !Task.isCancelled else { return }
                        switch event {
                        case .started(let id, let epoch)
                        where id.rawValue == session.session.accountId && epoch == session.epoch:
                            self?.syncing = true
                        case .finished(let id, let epoch, let result)
                        where id.rawValue == session.session.accountId && epoch == session.epoch:
                            self?.syncing = false
                            self?.offline = result.state == .offline
                            self?.refusedChanges.receive(result)
                        default: break
                        }
                    }
                })
        }
    }

    private func receive(outbox: [OutboxRecord]) {
        state.apply(outbox: outbox)
        confirmationCount = state.pending.count
        if outbox.isEmpty, !busy { showsPending = false }
    }

    public func stay() {
        guard !busy else { return }
        showsPending = false
    }

    public func signOut(discardPending: Bool = false) async {
        guard active, !busy, let controller, let session,
            !discardPending || showsPending
        else { return }
        busy = true
        let generation = generation
        defer {
            busy = false
            if state.outboxLoaded, state.pendingCount == 0 { showsPending = false }
        }
        do {
            guard await controller.activeSession() == session, active, self.generation == generation else { return }
            let result = try await controller.signOut(expected: session, discardPending: discardPending)
            guard active, self.generation == generation else { return }
            switch result {
            case .signedOut:
                stop()
            case .needsConfirmation(let count):
                guard await controller.activeSession() == session, active, self.generation == generation else { return }
                confirmationCount = count
                if let database {
                    let outbox = try await OutboxRepository(database: database).pending()
                    guard active, self.generation == generation else { return }
                    receive(outbox: outbox)
                }
                guard await controller.activeSession() == session, active, self.generation == generation else { return }
                showsPending = confirmationCount > 0
            }
            failure = nil
        } catch {
            if active, self.generation == generation { failure = error }
        }
    }

    public func stop() {
        refusedChanges.clear()
        active = false
        generation += 1
        for task in tasks { task.cancel() }
        tasks.removeAll()
        showsPending = false
        state = SettingsHomeState()
        session = nil
        confirmationCount = 0
        syncing = false
        offline = false
    }
    deinit { for task in tasks { task.cancel() } }
}

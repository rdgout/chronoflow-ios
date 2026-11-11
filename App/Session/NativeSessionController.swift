import AppCore
import Foundation
import LocalStore
import Reminders
import Sync
import TripWizard
import UIKit

@MainActor
final class NativeSessionController {
    let controller: SessionController
    let accounts: SessionAccountDatabase
    let model: AccountModel
    let sync: SessionSync?
    let reminders: ReminderService
    let reminderTaps: ReminderTapRouter
    private var reminderEvents: Task<Void, Never>?
    private let timeObservers: ReminderTimeObservers
    let wiper: AccountWiper
    let guestSecrets: any GuestSecretStore
    let guestWizardStore: GuestWizardStore
    lazy var readiness = StoredDataReadiness(controller: controller) { [accounts] id in
        guard let database = await accounts.activeDatabase() else { throw StoreFailure.closed }
        return try await AccountReadinessRepository(database: database).values(accountID: id)
    }
    private var gateRouter: SessionGateRouter?
    private var subscription: Task<Void, Never>?
    private let sourceFactory: (@Sendable (StoredSession) async -> any DataSource)?

    init(
        applicationSupport: URL, namespace: StorageNamespace, credentials: (any SessionStore)? = nil,
        guestSecrets: (any GuestSecretStore)? = nil,
        reminderCenter: any ReminderNotificationCenter = SystemReminderCenter(),
        accountStore: (@MainActor (SessionAccountDatabase) -> any SessionAccountStore)? = nil,
        syncScheduler: SyncScheduler = SyncScheduler(),
        syncPath: @escaping @Sendable () -> (any SyncPathMonitoring)? = { NetworkPathMonitor() },
        requestSync: @escaping @Sendable (UInt64) async -> Void = { _ in },
        source: (@Sendable (StoredSession) async -> any DataSource)? = nil,
        unauthorized: @escaping @Sendable (UInt64) async -> Void = { _ in },
        verification: @escaping @Sendable (UInt64) async -> Void = { _ in },
        signedOut: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        sourceFactory = source
        let taps = ReminderTapRouter()
        reminderTaps = taps
        let reminders = ReminderService(center: reminderCenter)
        self.reminders = reminders
        let model = AccountModel()
        self.model = model
        let accounts = SessionAccountDatabase(applicationSupport: applicationSupport, namespace: namespace) {
            await taps.clear()
            await reminders.detach()
            await model.detach()
        }
        self.accounts = accounts
        let credentials = credentials ?? KeychainSessionStore(namespace: namespace)
        let guestSecrets = guestSecrets ?? KeychainGuestSecretStore(namespace: namespace)
        self.guestSecrets = guestSecrets
        guestWizardStore = GuestWizardStore(applicationSupport: applicationSupport, namespace: namespace)
        let reference = SessionControllerReference()
        let sync = source.map {
            SessionSync(
                accounts: accounts, scheduler: syncScheduler, makePath: syncPath, source: $0,
                isCurrent: { session, epoch in
                    guard let current = await reference.value()?.activeSession() else { return false }
                    return current.session == session && current.epoch == epoch
                },
                unauthorized: { epoch in
                    if let controller = reference.value() { _ = try? await controller.unauthorized(epoch: epoch) }
                    await unauthorized(epoch)
                }, verification: verification)
        }
        self.sync = sync
        let wiper = AccountWiper(
            applicationSupport: applicationSupport, namespace: namespace, credentials: credentials,
            guestSecrets: guestSecrets)
        self.wiper = wiper
        var teardown = SessionTeardown()
        teardown.prepare = {
            try await accounts.close()
            try await wiper.recover()
        }
        teardown.pendingCount = {
            guard let database = await accounts.activeDatabase() else { throw StoreFailure.closed }
            return try await OutboxRepository(database: database).pending().count
        }
        teardown.flush = { _ = try await sync?.refreshNow() }
        teardown.beginWipe = { try await wiper.begin($0) }
        teardown.erase = { try await wiper.erase($0) }
        teardown.finishWipe = { try await wiper.finish() }
        teardown.logout = { session in
            if let source { try await source(session).signOut() }
        }
        teardown.detach = {
            await model.detach()
            await signedOut()
        }
        controller = SessionController(
            credentials: credentials, accounts: accountStore?(accounts) ?? accounts, teardown: teardown,
            stopSync: {
                await reminders.detach()
                await sync?.stop()
            },
            requestSync: { epoch in
                if let controller = reference.value() {
                    await sync?.requestStart(controller: controller, epoch: epoch)
                }
                await requestSync(epoch)
            })
        reference.set(controller)
        timeObservers = ReminderTimeObservers(service: reminders)
    }

    func deleteAccount(password: String, session: SessionSnapshot) async throws {
        guard let sync, await controller.activeSession() == session else { throw CancellationError() }
        try await sync.deleteAccount(password: password, session: session.session, epoch: session.epoch)
        _ = try await controller.signOut(expected: session, discardPending: true)
    }

    func accountSecurity(_ change: AccountSecurityChange, session: SessionSnapshot) async throws
        -> AccountSecurityResult
    {
        guard let sync else { throw DataFailure.unsupported(.security) }
        return try await sync.accountSecurity(change, session: session.session, epoch: session.epoch)
    }

    func routeAcceptedSession(
        _ result: SessionResult, method: AuthenticationMethod,
        navigator: RootNavigator, verification: @escaping @MainActor (UInt64) async -> Void
    ) async throws {
        observeGates(navigator: navigator, verification: verification)
        try await GuestSessionAcceptance(guest: guestWizardStore, secrets: guestSecrets).routeAcceptedSession(
            result, method: method, controller: controller, accounts: accounts, readiness: readiness,
            navigator: navigator, verification: verification)
    }

    func routeAcceptedSession(
        navigator: RootNavigator, verification: @escaping @MainActor (UInt64) async -> Void
    ) async {
        observeGates(navigator: navigator, verification: verification)
        await readiness.routeAcceptedSession(navigator: navigator, verification: verification)
    }

    func observeGates(navigator: RootNavigator, verification: @escaping @MainActor (UInt64) async -> Void) {
        guard gateRouter == nil else { return }
        let router = SessionGateRouter(
            controller: controller, readiness: readiness, navigator: navigator, verification: verification)
        gateRouter = router
        router.start()
    }

    func setActive(_ active: Bool) async {
        await sync?.setEnabled(active)
        if active {
            _ = try? await guestWizardStore.recover()
            await reminders.reschedule()
            do { try await controller.retryUnauthorized() } catch { return }
            await readiness.retry()
            if let current = await controller.activeSession() {
                await sync?.resume(session: current.session, epoch: current.epoch)
            }
        }
    }

    @discardableResult
    func refreshNow() async throws -> SyncResult? {
        return try await sync?.refreshNow()
    }

    func wizardDataSource(session: StoredSession) async -> (any DataSource)? { await sourceFactory?(session) }

    func wizardGenerationService(snapshot: SessionSnapshot) async throws -> TripGenerationService {
        guard let database = await accounts.activeDatabase(),
            let permit = await controller.mutationPermit(for: snapshot),
            let source = await sourceFactory?(snapshot.session),
            await controller.activeSession() == snapshot
        else { throw CancellationError() }
        let epoch = SyncEpoch(accountID: try AccountID(snapshot.session.accountId), generation: snapshot.epoch)
        return TripGenerationService(
            source: source,
            effects: .storing(
                database: database, source: source, epoch: epoch, permit: permit,
                requestSync: { [sync] in await sync?.requestSync() }))
    }

    func observe() {
        guard subscription == nil else { return }
        if let sync {
            reminderEvents = Task { [reminders] in
                for await event in await sync.events() {
                    guard !Task.isCancelled else { return }
                    if case .finished(_, _, let result) = event, result.state == .idle { await reminders.reschedule() }
                }
            }
        }
        subscription = Task { [weak self, controller, accounts, model, reminders] in
            for await update in await controller.updates() {
                guard !Task.isCancelled, self != nil else { return }
                let attachmentToken = model.attachmentToken
                guard await controller.epoch == update.epoch, await controller.presence == update.presence else {
                    continue
                }
                if case .signedIn(let id) = update.presence, let database = await accounts.activeDatabase(),
                    await database.accountID?.rawValue == id, await controller.epoch == update.epoch
                {
                    await reminders.attach(database: database)
                    guard await controller.epoch == update.epoch, await controller.presence == update.presence else {
                        await reminders.detach()
                        continue
                    }
                    await model.attach(
                        to: AccountRepository(database: database), epoch: update.epoch, ifCurrent: attachmentToken)
                } else if model.attachmentToken == attachmentToken {
                    await model.detach()
                }
            }
        }
    }

    func stopObserving() async {
        gateRouter?.stop()
        gateRouter = nil
        let previous = subscription
        subscription = nil
        previous?.cancel()
        await previous?.value
        let events = reminderEvents
        reminderEvents = nil
        events?.cancel()
        await events?.value
        await model.detach()
    }

    deinit {
        subscription?.cancel()
        reminderEvents?.cancel()
    }
}

nonisolated private final class SessionControllerReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var controller: SessionController?
    func set(_ value: SessionController) { lock.withLock { controller = value } }
    func value() -> SessionController? { lock.withLock { controller } }
}

import AppCore
import Foundation
import LocalStore
import Sync

@MainActor
final class NativeSessionController {
    let controller: SessionController
    let accounts: SessionAccountDatabase
    let model: AccountModel
    let sync: SessionSync?
    let wiper: AccountWiper
    lazy var readiness = StoredDataReadiness(controller: controller) { [accounts] id in
        guard let database = await accounts.activeDatabase() else { throw StoreFailure.closed }
        return try await AccountReadinessRepository(database: database).values(accountID: id)
    }
    private var subscription: Task<Void, Never>?

    init(
        applicationSupport: URL, namespace: StorageNamespace, credentials: (any SessionStore)? = nil,
        requestSync: @escaping @Sendable (UInt64) async -> Void = { _ in },
        source: (@Sendable (StoredSession) async -> any DataSource)? = nil,
        unauthorized: @escaping @Sendable (UInt64) async -> Void = { _ in },
        verification: @escaping @Sendable (UInt64) async -> Void = { _ in },
        signedOut: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        let model = AccountModel()
        self.model = model
        let accounts = SessionAccountDatabase(applicationSupport: applicationSupport, namespace: namespace) {
            await model.detach()
        }
        self.accounts = accounts
        let credentials = credentials ?? KeychainSessionStore(namespace: namespace)
        let reference = SessionControllerReference()
        let sync = source.map {
            SessionSync(
                accounts: accounts, makePath: { NetworkPathMonitor() }, source: $0,
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
        let wiper = AccountWiper(applicationSupport: applicationSupport, namespace: namespace, credentials: credentials)
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
            credentials: credentials, accounts: accounts, teardown: teardown, stopSync: { await sync?.stop() },
            requestSync: { epoch in
                if let current = await reference.value()?.activeSession(), current.epoch == epoch {
                    await sync?.start(session: current.session, epoch: epoch)
                }
                await requestSync(epoch)
            })
        reference.set(controller)
    }

    func setActive(_ active: Bool) async {
        await sync?.setEnabled(active)
        if active {
            do { try await controller.retryUnauthorized() } catch { return }
            await readiness.retry()
            if let current = await controller.activeSession() {
                await sync?.resume(session: current.session, epoch: current.epoch)
            }
        }
    }

    func refreshNow() async throws { _ = try await sync?.refreshNow() }

    func observe() {
        guard subscription == nil else { return }
        subscription = Task { [weak self, controller, accounts, model] in
            for await update in await controller.updates() {
                guard !Task.isCancelled, self != nil else { return }
                let attachmentToken = model.attachmentToken
                guard await controller.epoch == update.epoch, await controller.presence == update.presence else {
                    continue
                }
                if case .signedIn(let id) = update.presence, let database = await accounts.activeDatabase(),
                    await database.accountID?.rawValue == id, await controller.epoch == update.epoch
                {
                    await model.attach(
                        to: AccountRepository(database: database), epoch: update.epoch, ifCurrent: attachmentToken)
                } else if model.attachmentToken == attachmentToken {
                    await model.detach()
                }
            }
        }
    }

    func stopObserving() async {
        let previous = subscription
        subscription = nil
        previous?.cancel()
        await previous?.value
        await model.detach()
    }

    deinit { subscription?.cancel() }
}

nonisolated private final class SessionControllerReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var controller: SessionController?
    func set(_ value: SessionController) { lock.withLock { controller = value } }
    func value() -> SessionController? { lock.withLock { controller } }
}

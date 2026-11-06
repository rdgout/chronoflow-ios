import AppCore
import Foundation
import LocalStore

@MainActor
final class NativeSessionController {
    let controller: SessionController
    let accounts: SessionAccountDatabase
    let model: AccountModel
    let sync: SessionSync?
    private var subscription: Task<Void, Never>?

    init(
        applicationSupport: URL, namespace: StorageNamespace, credentials: (any SessionStore)? = nil,
        requestSync: @escaping @Sendable (UInt64) async -> Void = { _ in },
        source: (@Sendable (StoredSession) async -> any DataSource)? = nil,
        unauthorized: @escaping @Sendable (UInt64) async -> Void = { _ in },
        verification: @escaping @Sendable (UInt64) async -> Void = { _ in }
    ) {
        let model = AccountModel()
        self.model = model
        let accounts = SessionAccountDatabase(applicationSupport: applicationSupport, namespace: namespace) {
            await model.detach()
        }
        self.accounts = accounts
        let credentials = credentials ?? KeychainSessionStore(namespace: namespace)
        let sync = source.map {
            SessionSync(accounts: accounts, source: $0, unauthorized: unauthorized, verification: verification)
        }
        self.sync = sync
        controller = SessionController(
            credentials: credentials, accounts: accounts, stopSync: { await sync?.stop() },
            requestSync: { epoch in
                if let session = try? await credentials.readStoredSession() {
                    await sync?.start(session: session, epoch: epoch)
                }
                await requestSync(epoch)
            })
    }

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

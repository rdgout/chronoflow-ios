import AppCore
import LocalStore

public struct GuestSessionAcceptance: Sendable {
    private let guest: GuestWizardStore
    private let secrets: any GuestSecretStore

    public init(guest: GuestWizardStore, secrets: any GuestSecretStore) {
        self.guest = guest
        self.secrets = secrets
    }

    @MainActor public func routeAcceptedSession(
        _ result: SessionResult, method: AuthenticationMethod,
        controller: SessionController, accounts: SessionAccountDatabase, readiness: StoredDataReadiness,
        navigator: any Navigator, verification: @escaping @MainActor (UInt64) async -> Void
    ) async throws {
        try await Task { @MainActor in
            guard let snapshot = await controller.activeSession(), snapshot.session.accountId == result.account.id,
                snapshot.session.token == result.token, let database = await accounts.activeDatabase(),
                let permit = await controller.mutationPermit(for: snapshot)
            else { throw CancellationError() }
            try await accept(result, method: method, database: database, permit: permit)
            guard await controller.activeSession() == snapshot else { return }
            await readiness.routeAcceptedSession(navigator: navigator, verification: verification)
        }.value
    }

    public func accept(
        _ result: SessionResult, method: AuthenticationMethod,
        database: AccountDatabase, permit: SessionMutationPermit? = nil
    ) async throws {
        guard await database.accountID?.rawValue == result.account.id else { throw CancellationError() }
        let draft = try await guest.recover()
        let continuation = GuestContinuationRepository(database: database, permit: permit)
        if let id = result.tripId {
            try await continuation.store(.trip(id))
            try await secrets.delete(for: id)
        } else if let draft {
            switch method {
            case .password, .passkey:
                _ = try await MemberWizardStore(database: database, permit: permit).start(seed: draft)
                try await continuation.store(.memberWizard)
            case .twoFactor:
                try await continuation.store(.trips)
            case .signUp: return
            }
        }
        if let draft {
            if let token = draft.form.identity?.token { try await secrets.delete(for: token) }
            try await guest.discard(instance: draft.state.instance)
        }
    }
}

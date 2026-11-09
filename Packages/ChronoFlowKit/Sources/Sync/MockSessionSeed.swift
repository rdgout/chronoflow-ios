#if DEBUG
    import AppCore
    import Foundation
    import LocalStore

    public enum MockSessionSeed {
        public static func run(
            applicationSupport root: URL, namespace: StorageNamespace, credentials: any SessionStore,
            source: any DataSource, input: PasswordSignInInput, twoFactorCode: String
        ) async throws {
            let marker = root.appending(path: "signed-in-seed.done")
            // A completed fixture must never resurrect a session after sign-out on relaunch.
            guard !FileManager.default.fileExists(atPath: marker.path) else { return }
            let result: SessionResult
            switch try await source.signIn(input) {
            case .session(let session): result = session
            case .twoFactor(let challenge):
                result = try await source.completeTwoFactor(
                    TwoFactorInput(challengeId: challenge, proof: .code(twoFactorCode)))
            }
            let accounts = SessionAccountDatabase(applicationSupport: root, namespace: namespace)
            let controller = SessionController(credentials: credentials, accounts: accounts)
            do {
                try await controller.accept(result)
                guard let database = await accounts.activeDatabase(), let session = await controller.activeSession()
                else { throw SessionFailure.databaseUnavailable }
                let epoch = SyncEpoch(accountID: try AccountID(result.account.id), generation: session.epoch)
                _ = try await FullPull(database: database, source: source).run(epoch: epoch)
                try await accounts.close()
                try Data().write(to: marker, options: .atomic)
            } catch {
                try? await accounts.close()
                throw error
            }
        }
    }
#endif

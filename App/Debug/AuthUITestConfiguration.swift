#if DEBUG
    import AppCore
    import Auth
    import DataAccess
    import Foundation

    extension AuthUITestConfiguration {
        @MainActor func prefill(_ model: SignUpModel) {
            guard auditScreen == "sign-up", let state = auditState,
                !["form", "empty", "visible"].contains(state)
            else { return }
            model.editName("Traveller")
            model.editEmail(
                state == "taken" ? "demo@example.com" : state == "email" ? "invalid" : "new@example.com")
            let password = state == "password" ? "short" : "NewPassword123!"
            model.editPassword(password)
            model.editConfirmation(state == "confirmation" ? "different" : password)
        }

        @MainActor func prefill(_ model: ResetPasswordModel) {
            guard auditScreen == "reset", let state = auditState, state != "form" else { return }
            let password = state == "password" ? "short" : "NewPassword123!"
            model.editPassword(password)
            model.editConfirmation(state == "confirmation" ? "different" : password)
        }

        @MainActor func prepareChallenge(_ model: SignInModel) async {
            guard auditScreen == "two-factor" else { return }
            model.editEmail(MockScenarioValues.twoFactorEmail)
            model.editPassword(MockScenarioValues.password)
            await model.submitPassword()
        }

        nonisolated var credentials: KeychainSessionStore {
            KeychainSessionStore(service: StorageNamespace.mock.keychainService + ".uitest." + id)
        }

    }
#endif

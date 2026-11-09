#if DEBUG
    import AppCore
    import Auth
    import Foundation

    nonisolated struct AuthUITestConfiguration: Sendable {
        let id: String
        let offline: Bool
        let settingsPending: Bool
        let walkthroughPending: Bool
        let unverified: Bool
        let walkthroughSeen: Bool
        let auditScreen: String?
        let auditState: String?

        init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let value = environment["CF_AUTH_TEST_ID"], let uuid = UUID(uuidString: value) else { return nil }
            id = uuid.uuidString.lowercased()
            offline = environment["CF_AUTH_TEST_OFFLINE"] == "1"
            settingsPending = environment["CF_SETTINGS_TEST_PENDING"] == "1"
            walkthroughPending = environment["CF_WALKTHROUGH_TEST_PENDING"] == "1"
            unverified = environment["CF_AUTH_TEST_UNVERIFIED"] == "1"
            walkthroughSeen = environment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] == "1"
            auditScreen = environment["CF_AUTH_TEST_AUDIT_SCREEN"]
            auditState = environment["CF_AUTH_TEST_AUDIT_STATE"]
        }

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

        var credentials: KeychainSessionStore {
            KeychainSessionStore(service: StorageNamespace.mock.keychainService + ".uitest." + id)
        }

        func applicationSupport(in root: URL) -> URL {
            root.appending(path: "AuthUITests/\(id)")
        }
    }
#endif

#if DEBUG
    import AppCore
    import Foundation

    nonisolated struct AuthUITestConfiguration: Sendable {
        let id: String
        let offline: Bool
        let unverified: Bool
        let walkthroughSeen: Bool

        init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let value = environment["CF_AUTH_TEST_ID"], let uuid = UUID(uuidString: value) else { return nil }
            id = uuid.uuidString.lowercased()
            offline = environment["CF_AUTH_TEST_OFFLINE"] == "1"
            unverified = environment["CF_AUTH_TEST_UNVERIFIED"] == "1"
            walkthroughSeen = environment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] == "1"
        }

        var credentials: KeychainSessionStore {
            KeychainSessionStore(service: StorageNamespace.mock.keychainService + ".uitest." + id)
        }

        func applicationSupport(in root: URL) -> URL {
            root.appending(path: "AuthUITests/\(id)")
        }
    }
#endif

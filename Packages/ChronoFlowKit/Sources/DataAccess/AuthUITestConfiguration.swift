#if DEBUG
    import AppCore
    import Foundation

    public struct AuthUITestConfiguration: Sendable {
        public let fastLaunch: Bool
        public let mockDelay: TimeInterval
        public let id: String
        public let offline: Bool
        public let settingsPending: Bool
        public let walkthroughPending: Bool
        public let termsPending: Bool
        public let unverified: Bool
        public let walkthroughSeen: Bool
        public let refreshUpdatesTrip: Bool
        public let auditScreen: String?
        public let auditState: String?
        public let signedInAccount: String?
        public let verificationResendFailure: DataFailure?

        public init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard let value = environment["CF_AUTH_TEST_ID"], let uuid = UUID(uuidString: value) else { return nil }
            fastLaunch = environment["CF_UI_TEST_PROFILE"] == "screen"
            let delay = environment["CF_MOCK_DELAY"].flatMap(Double.init)
            mockDelay = delay.flatMap { $0.isFinite && (0...60).contains($0) ? $0 : nil } ?? 0
            id = uuid.uuidString.lowercased()
            offline = environment["CF_AUTH_TEST_OFFLINE"] == "1"
            settingsPending = environment["CF_SETTINGS_TEST_PENDING"] == "1"
            walkthroughPending = environment["CF_WALKTHROUGH_TEST_PENDING"] == "1"
            termsPending = environment["CF_AUTH_TEST_TERMS_PENDING"] == "1"
            unverified = environment["CF_AUTH_TEST_UNVERIFIED"] == "1"
            walkthroughSeen = environment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] == "1"
            refreshUpdatesTrip = environment["CF_REFRESH_TEST_UPDATE_TRIP"] == "1"
            auditScreen = environment["CF_AUTH_TEST_AUDIT_SCREEN"]
            auditState = environment["CF_AUTH_TEST_AUDIT_STATE"]
            signedInAccount = environment["CF_AUTH_TEST_SIGNED_IN"].flatMap {
                ["demo", "twofactor"].contains($0) ? $0 : nil
            }
            switch environment["CF_AUTH_TEST_VERIFY_STATE"] {
            case "throttle", "failedThrottle":
                verificationResendFailure = .throttled(retryAfterSeconds: 60, status: 429)
            case "server", "failedServer": verificationResendFailure = .server(status: 503)
            case "offline", "failedOffline": verificationResendFailure = .offline
            default: verificationResendFailure = nil
            }
        }

        public func applicationSupport(in root: URL) -> URL {
            root.appending(path: "AuthUITests/\(id)")
        }
    }
#endif

import AppCore
import DataAccess
import Foundation
import Reminders

#if DEBUG
    import LocalStore
    import Sync
#endif

nonisolated struct AppServices: Sendable {
    enum Failure: Error { case invalidReadiness, applicationSupportUnavailable }
    let signedOutReadiness: Bool
    let factory: DataSourceFactory
    private let mockDelay: @Sendable () -> TimeInterval
    private let isolatedMockStore: (any MockStateStore)?
    var namespace: StorageNamespace { factory.namespace }
    #if DEBUG
        private let authTest: AuthUITestConfiguration?
        private let authTestSeed: MockServerState?
        private let timelineSeed: MockServerState?
        private let refreshScenario: RefreshUITestScenario?
        var authUITestEnabled: Bool { authTest != nil }
        var fastUITestLaunch: Bool { authTest?.fastLaunch == true }

        func prepareRefreshUITest() async { await refreshScenario?.arm() }
    #endif

    func sessionCredentials() -> KeychainSessionStore {
        #if DEBUG
            if timelineSeed != nil {
                return KeychainSessionStore(service: StorageNamespace.mock.keychainService + ".timeline-fixtures")
            }
            if let authTest { return authTest.credentials }
        #endif
        return KeychainSessionStore(namespace: namespace)
    }

    func reminderCenter(arguments: [String] = ProcessInfo.processInfo.arguments) -> any ReminderNotificationCenter {
        #if DEBUG
            if authUITestEnabled {
                let index = arguments.firstIndex(of: "-cf.notificationAuthorization")
                let permission = index.flatMap { index in
                    arguments.indices.contains(index + 1) ? ReminderPermission(rawValue: arguments[index + 1]) : nil
                }
                return MockReminderCenter(permission: permission ?? .undetermined)
            }
        #endif
        return SystemReminderCenter()
    }

    private func makeMock(applicationSupport: URL, bearer: @escaping @Sendable () async throws -> String?)
        -> MockDataSource
    {
        #if DEBUG
            if let timelineSeed {
                return MockDataSource(
                    store: isolatedMockStore ?? MemoryMockStateStore(), seed: timelineSeed, delay: mockDelay,
                    bearer: bearer)
            }
            if let authTest {
                return MockDataSource(
                    store: isolatedMockStore ?? FileMockStateStore(applicationSupport: applicationSupport),
                    seed: authTestSeed,
                    offline: authTest.offline,
                    mutationsOffline: authTest.settingsPending || authTest.walkthroughPending || authTest.termsPending,
                    remoteTripUpdate: { await refreshScenario?.consume() ?? false },
                    delay: mockDelay,
                    // MockDataSource clamps ordinary latency to 300–800 ms; UI fixtures use their exact opt-in delay.
                    sleep: { _ in
                        if authTest.mockDelay > 0 { try await Task.sleep(for: .seconds(authTest.mockDelay)) }
                    }, bearer: bearer)
            }
        #endif
        return MockDataSource(
            store: isolatedMockStore ?? FileMockStateStore(applicationSupport: applicationSupport),
            delay: mockDelay, bearer: bearer)
    }

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        testing: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        mockDelay: (@Sendable () -> TimeInterval)? = nil
    ) throws {
        #if DEBUG
            let requestedAuthTest = AuthUITestConfiguration(environment: environment)
            self.mockDelay = mockDelay ?? { requestedAuthTest?.mockDelay ?? Double.random(in: 0.3...0.8) }
            isolatedMockStore =
                (requestedAuthTest?.fastLaunch == true
                    || arguments.contains("-cf.isolatedMockServer")
                    || arguments.contains("-cf.timeline-fixtures"))
                ? MemoryMockStateStore() : nil
        #else
            self.mockDelay = mockDelay ?? { Double.random(in: 0.3...0.8) }
            isolatedMockStore = nil
        #endif
        switch info["CHRONOFLOW_READINESS"] as? String ?? "native" {
        case "native": signedOutReadiness = false
        case "signed-out": signedOutReadiness = true
        default: throw Failure.invalidReadiness
        }
        #if DEBUG
            let release = false
        #else
            let release = true
        #endif
        #if DEBUG
            let authTestRequested = requestedAuthTest != nil
        #else
            let authTestRequested = false
        #endif
        factory = try DataSourceFactory(
            setting: info["CHRONOFLOW_DATA_SOURCE"] as? String ?? "mock",
            baseURL: info["CHRONOFLOW_API_BASE_URL"] as? String ?? "https://api.chronoflow.net/v1",
            release: release, testing: testing || authTestRequested)
        #if DEBUG
            timelineSeed =
                try factory.namespace == .mock && arguments.contains("-cf.timeline-fixtures")
                ? MockAppSeed.make(now: Date(), walkthroughSeen: true, includeTimelinePerformanceTrips: true) : nil
            authTest = requestedAuthTest
            refreshScenario = requestedAuthTest?.refreshUpdatesTrip == true ? RefreshUITestScenario() : nil
            authTestSeed = try authTest.map {
                var seed = try MockAppSeed.make(
                    now: Date(), unverified: $0.unverified, walkthroughSeen: $0.walkthroughSeen,
                    termsPending: $0.termsPending)
                if environment["CF_REFRESH_TEST_EMPTY_TRIPS"] == "1" {
                    for id in seed.accounts.keys {
                        seed.accounts[id]?.trips = []
                        seed.accounts[id]?.details = [:]
                    }
                }
                return try wizardUITestSeed(SettingsBoardCaptureFixture.seed(seed))
            }
        #endif
    }
    static func launchConfiguration() async throws -> (AppServices, URL?) {
        assert(!Thread.isMainThread)
        #if DEBUG
            return try await uiTestLaunchConfiguration(
                environment: ProcessInfo.processInfo.environment, arguments: ProcessInfo.processInfo.arguments)
        #else
            let services = try AppServices()
            let root =
                services.signedOutReadiness
                ? nil
                : FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            return (services, root)
        #endif
    }

    #if DEBUG
        static func uiTestLaunchConfiguration(
            environment: [String: String], arguments: [String], reset: Bool = false,
            applicationSupport: URL? = nil
        ) async throws -> (AppServices, URL?) {
            assert(!Thread.isMainThread)
            let services = try AppServices(environment: environment, arguments: arguments)
            var root =
                services.signedOutReadiness
                ? nil
                : applicationSupport
                    ?? FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first
            if services.timelineSeed != nil, let support = root {
                root = support.appending(path: "TimelineFixtures")
            } else if let test = services.authTest, let support = root {
                root = test.applicationSupport(in: support)
            }
            if let root {
                if reset, services.authTest != nil {
                    try await MockSessionSeed.reset(
                        applicationSupport: root, credentials: services.sessionCredentials())
                }
                try await services.seedSignedIn(applicationSupport: root)
            }
            return (services, root)
        }
    #endif

    #if DEBUG
        func seedSignedIn(applicationSupport root: URL) async throws {
            guard let test = authTest, let account = test.signedInAccount else { return }
            let credentials = test.credentials
            let source = MockDataSource(
                store: isolatedMockStore ?? FileMockStateStore(applicationSupport: root), seed: authTestSeed,
                delay: { 0 }, sleep: { _ in }, bearer: { try await credentials.readStoredSession()?.token })
            try await MockSessionSeed.run(
                applicationSupport: root, namespace: namespace, credentials: credentials, source: source,
                input: PasswordSignInInput(
                    email: account == "demo" ? MockScenarioValues.demoEmail : MockScenarioValues.twoFactorEmail,
                    password: MockScenarioValues.password, deviceID: test.id, deviceName: "UI test"),
                twoFactorCode: MockScenarioValues.twoFactorCode)

        }
    #endif

    func makeDataSource(applicationSupport: URL, session: StoredSession) -> any DataSource {
        assert(!Thread.isMainThread)
        return factory.make {
            makeMock(applicationSupport: applicationSupport, bearer: { session.token })
        } api: {
            APIDataSource(client: APIClient(baseURL: factory.baseURL, bearer: { session.token }))
        }
    }

    func makeDataSource(applicationSupport: URL, credentials: any SessionStore) -> any DataSource {
        factory.make {
            makeMock(
                applicationSupport: applicationSupport, bearer: { try await credentials.readStoredSession()?.token })
        } api: {
            APIDataSource(
                client: APIClient(
                    baseURL: factory.baseURL,
                    bearer: {
                        try await credentials.readStoredSession()?.token
                    }))
        }
    }
}

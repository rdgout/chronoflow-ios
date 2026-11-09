import AppCore
import DataAccess
import Foundation
import Reminders

nonisolated struct AppServices: Sendable {
    enum Failure: Error { case invalidReadiness, applicationSupportUnavailable }
    let signedOutReadiness: Bool
    let factory: DataSourceFactory
    private let isolatedMockStore: (any MockStateStore)?
    var namespace: StorageNamespace { factory.namespace }
    #if DEBUG
        private let authTest: AuthUITestConfiguration?
        private let authTestSeed: MockServerState?
        private let timelineSeed: MockServerState?
        private let refreshScenario: RefreshUITestScenario?
        var authUITestEnabled: Bool { authTest != nil }

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
                    store: isolatedMockStore ?? MemoryMockStateStore(), seed: timelineSeed, bearer: bearer)
            }
            if let authTest {
                return MockDataSource(
                    store: FileMockStateStore(applicationSupport: applicationSupport),
                    seed: authTestSeed,
                    offline: authTest.offline,
                    mutationsOffline: authTest.settingsPending || authTest.walkthroughPending || authTest.termsPending,
                    remoteTripUpdate: { await refreshScenario?.consume() ?? false },
                    bearer: bearer)
            }
        #endif
        return MockDataSource(
            store: isolatedMockStore ?? FileMockStateStore(applicationSupport: applicationSupport), bearer: bearer)
    }

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        testing: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        #if DEBUG
            isolatedMockStore =
                (ProcessInfo.processInfo.arguments.contains("-cf.isolatedMockServer")
                    || ProcessInfo.processInfo.arguments.contains("-cf.timeline-fixtures"))
                ? MemoryMockStateStore() : nil
        #else
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
            let requestedAuthTest = AuthUITestConfiguration(environment: environment)
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
                try factory.namespace == .mock && ProcessInfo.processInfo.arguments.contains("-cf.timeline-fixtures")
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
    static func launchConfiguration() throws -> (AppServices, URL?) {
        assert(!Thread.isMainThread)
        let services = try AppServices()
        var root =
            services.signedOutReadiness
            ? nil
            : FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        #if DEBUG
            if services.timelineSeed != nil, let support = root {
                root = support.appending(path: "TimelineFixtures")
            } else if let test = services.authTest, let support = root {
                root = test.applicationSupport(in: support)
            }
        #endif
        return (services, root)
    }

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

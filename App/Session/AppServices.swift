import AppCore
import DataAccess
import Foundation

nonisolated struct AppServices: Sendable {
    enum Failure: Error { case invalidReadiness, applicationSupportUnavailable }
    let signedOutReadiness: Bool
    let factory: DataSourceFactory
    private let isolatedMockStore: (any MockStateStore)?
    var namespace: StorageNamespace { factory.namespace }
    #if DEBUG
        private let authTest: AuthUITestConfiguration?
        private let authTestSeed: MockServerState?
        var authUITestEnabled: Bool { authTest != nil }
    #endif

    func sessionCredentials() -> KeychainSessionStore {
        #if DEBUG
            if let authTest { return authTest.credentials }
        #endif
        return KeychainSessionStore(namespace: namespace)
    }

    private func makeMock(applicationSupport: URL, bearer: @escaping @Sendable () async throws -> String?)
        -> MockDataSource
    {
        #if DEBUG
            if let authTest {
                return MockDataSource(
                    store: FileMockStateStore(applicationSupport: applicationSupport),
                    seed: authTestSeed,
                    offline: authTest.offline, bearer: bearer)
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
                ProcessInfo.processInfo.arguments.contains("-cf.isolatedMockServer")
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
        factory = try DataSourceFactory(
            setting: info["CHRONOFLOW_DATA_SOURCE"] as? String ?? "mock",
            baseURL: info["CHRONOFLOW_API_BASE_URL"] as? String ?? "https://api.chronoflow.net/v1",
            release: release, testing: testing)
        #if DEBUG
            authTest = factory.source == .mock ? AuthUITestConfiguration(environment: environment) : nil
            authTestSeed = try authTest.map {
                try MockAppSeed.make(now: Date(), unverified: $0.unverified, walkthroughSeen: $0.walkthroughSeen)
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
            if let test = services.authTest, let support = root { root = test.applicationSupport(in: support) }
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

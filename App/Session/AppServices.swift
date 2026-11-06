import AppCore
import DataAccess
import Foundation

nonisolated struct AppServices: Sendable {
    enum Failure: Error { case invalidReadiness, applicationSupportUnavailable }
    let signedOutReadiness: Bool
    let factory: DataSourceFactory
    private let isolatedMockStore: (any MockStateStore)?
    var namespace: StorageNamespace { factory.namespace }

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        testing: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
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
    }
    static func launchConfiguration() throws -> (AppServices, URL?) {
        assert(!Thread.isMainThread)
        let services = try AppServices()
        let root =
            services.signedOutReadiness
            ? nil
            : FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        return (services, root)
    }

    func makeDataSource(applicationSupport: URL, session: StoredSession) -> any DataSource {
        assert(!Thread.isMainThread)
        return factory.make {
            MockDataSource(
                store: isolatedMockStore ?? FileMockStateStore(applicationSupport: applicationSupport),
                bearer: { session.token })
        } api: {
            APIDataSource(client: APIClient(baseURL: factory.baseURL, bearer: { session.token }))
        }
    }

    func makeDataSource(applicationSupport: URL, credentials: any SessionStore) -> any DataSource {
        factory.make {
            MockDataSource(
                store: isolatedMockStore ?? FileMockStateStore(applicationSupport: applicationSupport),
                bearer: {
                    try await credentials.readStoredSession()?.token
                })
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

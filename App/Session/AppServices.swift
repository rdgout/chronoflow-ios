import AppCore
import DataAccess
import Foundation

struct AppServices {
    let factory: DataSourceFactory
    var namespace: StorageNamespace { factory.namespace }

    init(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        testing: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    ) throws {
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
}

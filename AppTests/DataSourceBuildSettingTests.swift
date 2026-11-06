import AppCore
import DataAccess
import Foundation
import Testing

@testable import ChronoFlow

@MainActor @Suite struct DataSourceBuildSettingTests {
    @Test func builtSettingsAndTestSelection() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(["mock", "api"].contains(try #require(info["CHRONOFLOW_DATA_SOURCE"] as? String)))
        _ = try APIBaseURL(try #require(info["CHRONOFLOW_API_BASE_URL"] as? String), release: true)
        let services = try AppServices()
        #expect(services.factory.source == .mock)
        #expect(services.namespace == .mock)
    }
    @Test func explicitAPIRemainsMockUnderTests() throws {
        let services = try AppServices(
            info: ["CHRONOFLOW_DATA_SOURCE": "api", "CHRONOFLOW_API_BASE_URL": "https://api.example.test/v1"],
            testing: true)
        #expect(services.factory.source == .mock)
        #expect(services.namespace.keychainService == StorageNamespace.mock.keychainService)
        #expect(throws: DataSourceConfigurationFailure.invalidSource) {
            try AppServices(info: ["CHRONOFLOW_DATA_SOURCE": "invalid"])
        }
    }
}

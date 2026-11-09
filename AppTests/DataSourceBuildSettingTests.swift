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

@MainActor @Suite struct DataSourceFactoryHostedTests {
    @Test func sourceConstructionIsLazyAndMockOnly() async throws {
        let credentials = FactoryCredentialProbe()
        let services = try AppServices(
            info: ["CHRONOFLOW_DATA_SOURCE": "api", "CHRONOFLOW_API_BASE_URL": "https://api.example.invalid/v1"],
            testing: true)
        let source = services.makeDataSource(
            applicationSupport: URL(fileURLWithPath: "/unused-factory-test"), credentials: credentials)
        #expect(source is MockDataSource)
        #expect(await credentials.readCount == 0)
    }
}

private actor FactoryCredentialProbe: SessionStore {
    var readCount = 0
    func read() -> Data? {
        readCount += 1
        return nil
    }
    func write(_ data: Data) {}
    func delete() {}
}

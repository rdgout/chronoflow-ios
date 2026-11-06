import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct DataSourceSelectionTests {
    @Test func defaultsAndIsolation() throws {
        let factory = try DataSourceFactory(release: false, testing: false)
        #expect(factory.source == .mock)
        #expect(factory.namespace == .mock)
        #expect(try DataSourceFactory(setting: "api", release: true, testing: true).source == .mock)
        #expect(try DataSourceFactory(setting: "api", release: false, testing: false).source == .api)
        #expect(StorageNamespace.mock.directoryName != StorageNamespace.api.directoryName)
        #expect(StorageNamespace.mock.keychainService != StorageNamespace.api.keychainService)
    }
    @Test func rejectInvalidSettings() {
        for setting in ["", "API", "other", "$(CHRONOFLOW_DATA_SOURCE)"] {
            #expect(throws: DataSourceConfigurationFailure.invalidSource) {
                try DataSourceFactory(setting: setting, release: false, testing: true)
            }
        }
        for url in [
            "/v1", "https://", "file:///v1", "https://u:p@api.test/v1", "https://api.test/v1?q=x",
            "https://api.test/v1#x", "https://api.test/../v1",
        ] {
            #expect(throws: DataSourceConfigurationFailure.invalidBaseURL) { try APIBaseURL(url, release: false) }
        }
        #expect(throws: DataSourceConfigurationFailure.invalidBaseURL) {
            try APIBaseURL("http://localhost/v1", release: true)
        }
        #expect(throws: Never.self) { try APIBaseURL("http://localhost/v1", release: false) }
    }
}

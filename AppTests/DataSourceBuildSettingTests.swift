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
    #if DEBUG
        @Test(arguments: [false, true])
        func defaultAppMockUsesRNSeed(storedSession: Bool) async throws {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let services = try AppServices(info: [:], testing: false)
            let source: any DataSource
            if storedSession {
                source = await Task.detached {
                    services.makeDataSource(
                        applicationSupport: root, session: StoredSession(token: "unused", accountId: UUID().uuidString))
                }.value
            } else {
                source = services.makeDataSource(applicationSupport: root, credentials: FactoryCredentialProbe())
            }
            let mock = try #require(source as? MockDataSource)
            #expect(!FileManager.default.fileExists(atPath: FileMockStateStore(applicationSupport: root).url.path))
            #expect(try await mock.inbox().isEmpty)
            let state = try await Task.detached {
                try FileMockStateStore(applicationSupport: root).load()
            }.value
            let accounts = try #require(state?.accounts)
            #expect(accounts.count == 2)
            let demo = try #require(accounts.values.first { $0.twoFactorCode == nil })
            guard
                case .session(let result) = try await source.signIn(
                    PasswordSignInInput(
                        email: demo.snapshot.email, password: demo.password, deviceID: UUID().uuidString,
                        deviceName: "iPhone"))
            else {
                Issue.record("Expected seeded demo sign-in")
                return
            }
            #expect(result.account.hasVerifiedEmail)
            #expect(demo.trips.count == 7)
            let twoFactor = try #require(accounts.values.first { $0.twoFactorCode != nil })
            guard
                case .twoFactor = try await source.signIn(
                    PasswordSignInInput(
                        email: twoFactor.snapshot.email, password: twoFactor.password, deviceID: UUID().uuidString,
                        deviceName: "iPhone"))
            else {
                Issue.record("Expected seeded two-factor challenge")
                return
            }
        }
    #endif

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

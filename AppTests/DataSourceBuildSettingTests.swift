import AppCore
import Auth
import Foundation
import Reminders
import Testing

@testable import ChronoFlow
@testable import DataAccess

@MainActor @Suite struct DataSourceBuildSettingTests {
    #if DEBUG
        @Test(arguments: [
            ([], ReminderPermission.undetermined),
            (["-cf.notificationAuthorization"], .undetermined),
            (["-cf.notificationAuthorization", "invalid"], .undetermined),
            (["-cf.notificationAuthorization", "undetermined"], .undetermined),
            (["-cf.notificationAuthorization", "blocked"], .blocked),
            (["-cf.notificationAuthorization", "granted"], .granted),
        ])
        func isolatedUIFixturesAlwaysUseFakeNotifications(arguments: [String], permission: ReminderPermission)
            async throws
        {
            let services = try AppServices(
                info: ["CHRONOFLOW_DATA_SOURCE": "api"], testing: false,
                environment: ["CF_AUTH_TEST_ID": UUID().uuidString])
            let center = try #require(services.reminderCenter(arguments: arguments) as? MockReminderCenter)
            #expect(await center.permission() == permission)
            #expect(await center.permissionRequestCount == 0)
            #expect(await center.requestPermission() == (permission == .undetermined ? .granted : permission))
        }

        @Test func normalLaunchUsesSystemNotificationsEvenWithTestArguments() throws {
            let services = try AppServices(info: [:], testing: false, environment: [:])
            #expect(
                services.reminderCenter(arguments: ["-cf.notificationAuthorization", "granted"]) is SystemReminderCenter
            )
        }

        @Test func auditPrefillsRequireAnIsolatedMockFixtureAndRetainFailureInputs() throws {
            let audit = ["CF_AUTH_TEST_AUDIT_SCREEN": "sign-up", "CF_AUTH_TEST_AUDIT_STATE": "confirmation"]
            #expect(AuthUITestConfiguration(environment: audit) == nil)
            var environment = audit
            environment["CF_AUTH_TEST_ID"] = UUID().uuidString
            let configuration = try #require(AuthUITestConfiguration(environment: environment))
            let source = MockDataSource(seed: MockServerState())
            let signup = SignUpModel(
                source: source, navigation: AuthNavigation(), deviceIdentity: { UUID().uuidString },
                deviceName: "test", accept: { _ in })
            configuration.prefill(signup)
            #expect(signup.name == "Traveller" && signup.email == "new@example.com")
            #expect(signup.password == "NewPassword123!" && signup.confirmation == "different")
            let reset = ResetPasswordModel(
                link: ResetPasswordLink(token: "test", email: "demo@example.com"), source: source,
                navigation: AuthNavigation())
            configuration.prefill(reset)
            #expect(reset.password.isEmpty && reset.confirmation.isEmpty)
            environment["CF_AUTH_TEST_AUDIT_SCREEN"] = "reset"
            environment["CF_AUTH_TEST_AUDIT_STATE"] = "server"
            try #require(AuthUITestConfiguration(environment: environment)).prefill(reset)
            #expect(reset.password == "NewPassword123!" && reset.confirmation == "NewPassword123!")
        }

        @Test func recoveryUIFixtureForcesMockEvenWhenTheBuildRequestsAPI() throws {
            let services = try AppServices(
                info: ["CHRONOFLOW_DATA_SOURCE": "api"], testing: false,
                environment: ["CF_AUTH_TEST_ID": UUID().uuidString])
            #expect(services.factory.source == .mock && services.authUITestEnabled)
        }
    #endif

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
        @Test(arguments: [false, true], [false, true])
        func authOfflineFlagReachesBothMockFactories(offline: Bool, storedSession: Bool) async throws {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let services = try AppServices(
                info: [:], testing: false,
                environment: ["CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_OFFLINE": offline ? "1" : "0"])
            let source: any DataSource
            if storedSession {
                source = await Task.detached {
                    services.makeDataSource(
                        applicationSupport: root, session: StoredSession(token: "unused", accountId: UUID().uuidString))
                }.value
            } else {
                source = services.makeDataSource(applicationSupport: root, credentials: FactoryCredentialProbe())
            }
            #expect(source is MockDataSource)
            do {
                _ = try await source.signIn(
                    PasswordSignInInput(
                        email: MockScenarioValues.demoEmail, password: MockScenarioValues.password,
                        deviceID: UUID().uuidString, deviceName: "test"))
                #expect(!offline, "Offline launch configuration must reach MockDataSource")
            } catch {
                #expect(offline)
                #expect(error as? DataFailure == .offline)
            }
        }

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

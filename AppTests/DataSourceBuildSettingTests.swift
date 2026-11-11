import AppCore
import Auth
import Foundation
import LocalStore
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
            let source = MockDataSource(seed: MockServerState(), delay: { 0 }, sleep: { _ in })
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

}

@MainActor @Suite struct DataSourceFactoryHostedTests {
    #if DEBUG
        @Test func auditChallengeSeedRequiresExplicitScreenAndNeverAcceptsSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let credentials = FactoryCredentialProbe()
            let controller = SessionController(
                credentials: credentials, accounts: SessionAccountDatabase(applicationSupport: root, namespace: .mock))
            let source = MockDataSource(seed: try MockAppSeed.make(now: Date()), delay: { 0 }, sleep: { _ in })
            let model = SignInModel(
                source: source, session: controller, deviceIdentity: { UUID().uuidString }, deviceName: "test",
                accepted: { _ in Issue.record("Challenge seed accepted a session") })
            var environment = ["CF_AUTH_TEST_ID": UUID().uuidString]
            await AuthUITestConfiguration(environment: environment)?.prepareChallenge(model)
            #expect(model.email.isEmpty && model.navigation.challengeID == nil)
            environment["CF_AUTH_TEST_AUDIT_SCREEN"] = "two-factor"
            await AuthUITestConfiguration(environment: environment)?.prepareChallenge(model)
            #expect(model.navigation.challengeID != nil && model.twoFactor != nil)
            #expect(model.password.isEmpty && model.twoFactor?.code.isEmpty == true)
            #expect(await controller.activeSession() == nil)
            #expect(!FileManager.default.fileExists(atPath: root.path))
        }

        @Test func signedInSeedWiresAuthConfigurationToRestorableMockSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let services = try AppServices(
                info: [:], testing: true,
                environment: [
                    "CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_SIGNED_IN": "twofactor",
                    "CF_AUTH_TEST_UNVERIFIED": "1", "CF_AUTH_TEST_OFFLINE": "1",
                ], mockDelay: { 0 })
            try await services.seedSignedIn(applicationSupport: root)
            let credentials = services.sessionCredentials()
            defer { Task { try? await credentials.delete() } }
            let stored = try #require(try await credentials.readStoredSession())
            #expect(stored.accountId == MockScenarioValues.twoFactorID)
            let accounts = SessionAccountDatabase(applicationSupport: root, namespace: services.namespace)
            #expect(
                try await SessionController(credentials: credentials, accounts: accounts).restore()
                    == .signedIn(accountID: stored.accountId))
            let database = try #require(await accounts.activeDatabase())
            #expect(try await AccountRepository(database: database).account()?.hasVerifiedEmail == false)
            try await accounts.close()
            try await credentials.delete()
        }

        @Test func signedInSeedRequiresAuthTestGateAndKnownAccount() async throws {
            for environment in [
                ["CF_AUTH_TEST_SIGNED_IN": "demo"],
                ["CF_AUTH_TEST_ID": "invalid", "CF_AUTH_TEST_SIGNED_IN": "demo"],
                ["CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_SIGNED_IN": "unknown"],
            ] {
                let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                let services = try AppServices(info: [:], testing: true, environment: environment)
                try await Task.detached { try await services.seedSignedIn(applicationSupport: root) }.value
                #expect(!FileManager.default.fileExists(atPath: root.path))
            }
        }

        @Test(arguments: [false, true])
        func defaultMockFactoriesUseLazyPersistentStore(storedSession: Bool) async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let services = try AppServices(info: [:], testing: false, environment: [:], mockDelay: { 0 })
            func makeSource() async -> MockDataSource? {
                let source: any DataSource
                if storedSession {
                    source = await Task.detached {
                        services.makeDataSource(
                            applicationSupport: root,
                            session: StoredSession(token: "unused", accountId: MockScenarioValues.demoID))
                    }.value
                } else {
                    source = services.makeDataSource(applicationSupport: root, credentials: FactoryCredentialProbe())
                }
                return source as? MockDataSource
            }
            let source = try #require(await makeSource())
            #expect(!FileManager.default.fileExists(atPath: FileMockStateStore(applicationSupport: root).url.path))
            #expect(try await source.inbox().isEmpty)
            let initial = try #require(
                try await Task.detached { try FileMockStateStore(applicationSupport: root).load() }.value)
            #expect(Set(initial.accounts.keys) == [MockScenarioValues.demoID, MockScenarioValues.twoFactorID])
            #expect(initial.accounts[MockScenarioValues.demoID]?.trips.count == 7)
            #expect(initial.accounts[MockScenarioValues.demoID]?.snapshot.hasVerifiedEmail == true)
            #expect(initial.accounts[MockScenarioValues.twoFactorID]?.twoFactorCode != nil)
            try await source.requestPasswordReset(email: MockScenarioValues.demoEmail)
            let mail = try await source.inbox()
            #expect(mail.count == 1)
            let recreated = try #require(await makeSource())
            #expect(try await recreated.inbox() == mail)
        }

        @Test(arguments: [false, true], [false, true])
        func authOfflineFlagReachesBothMockFactories(offline: Bool, storedSession: Bool) async throws {
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let services = try AppServices(
                info: [:], testing: false,
                environment: ["CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_OFFLINE": offline ? "1" : "0"],
                mockDelay: { 0 })
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

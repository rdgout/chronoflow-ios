#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import LocalStore
    import Testing
    import Sync

    @testable import ChronoFlow

    @MainActor @Suite struct UITestReseedTests {
        @Test func screenSeedSharesOneMemoryServerAcrossBothFactories() async throws {
            let support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: support) }
            let environment = [
                "CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen", "CF_AUTH_TEST_SIGNED_IN": "demo",
                "CF_AUTH_TEST_WALKTHROUGH_SEEN": "1",
            ]
            let (services, root) = try await Task.detached {
                try await AppServices.uiTestLaunchConfiguration(
                    environment: environment, arguments: [], applicationSupport: support)
            }.value
            let directory = try #require(root)
            let credentials = services.sessionCredentials()
            let stored = try #require(try await credentials.readStoredSession())
            let bound = try #require(
                await Task.detached {
                    services.makeDataSource(applicationSupport: directory, session: stored) as? MockDataSource
                }.value)
            let dynamic = try #require(
                services.makeDataSource(applicationSupport: directory, credentials: credentials) as? MockDataSource)
            #expect(try await bound.fetchIdentity().id == MockScenarioValues.demoID)
            #expect(try await dynamic.fetchIdentity().id == MockScenarioValues.demoID)
            try await bound.requestPasswordReset(email: MockScenarioValues.demoEmail)
            #expect(try await dynamic.inbox().count == 1)
            #expect(!FileManager.default.fileExists(atPath: FileMockStateStore(applicationSupport: directory).url.path))
            try await MockSessionSeed.reset(applicationSupport: directory, credentials: credentials)
        }

        @Test func auditRoutesPrepareActualNavigationAndResetMailWithoutAcceptingASession() async throws {
            for screen in ["sign-in", "sign-up", "forgot", "reset"] {
                let environment = [
                    "CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen",
                    "CF_AUTH_TEST_AUDIT_SCREEN": screen, "CF_AUTH_TEST_AUDIT_STATE": "form",
                ]
                let support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: support) }
                let (services, root) = try await Task.detached {
                    try await AppServices.uiTestLaunchConfiguration(
                        environment: environment, arguments: [], applicationSupport: support)
                }.value
                let directory = try #require(root)
                let native = NativeSessionController(
                    applicationSupport: directory, namespace: services.namespace,
                    credentials: services.sessionCredentials())
                let navigator = RootNavigator()
                let auth = AuthSessionServices(
                    services: services, applicationSupport: directory, nativeSession: native, navigator: navigator,
                    verification: { _ in })
                try await auth.prepareUITestRoute(
                    try #require(AuthUITestConfiguration(environment: environment)), navigator: navigator)
                #expect(navigator.route == .signIn)
                #expect(await native.controller.activeSession() == nil)
                switch screen {
                case "sign-in": #expect(auth.model.navigation.path.isEmpty)
                case "sign-up": #expect(auth.model.navigation.path == [.signUp])
                case "forgot": #expect(auth.model.navigation.path == [.forgot])
                default:
                    guard case .reset(let link)? = auth.model.navigation.path.last else {
                        Issue.record("Missing reset mail route")
                        continue
                    }
                    #expect(link.email == MockScenarioValues.demoEmail)
                    #expect(!link.token.isEmpty)
                }
                try await UITestSessionFixture.tearDown(native: native, auth: auth)
                try await MockSessionSeed.reset(
                    applicationSupport: directory, credentials: services.sessionCredentials())
            }
        }

        @Test func resetUsesColdConfigurationAndStoredRouteAfterDirtyAccountTeardown() async throws {
            let support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: support) }
            let environment = [
                "CF_AUTH_TEST_ID": UUID().uuidString, "CF_UI_TEST_PROFILE": "screen",
                "CF_AUTH_TEST_SIGNED_IN": "twofactor", "CF_AUTH_TEST_WALKTHROUGH_SEEN": "1",
                "CF_AUTH_TEST_TERMS_PENDING": "1",
            ]
            func prepare(reset: Bool) async throws -> (AppServices, URL, NativeSessionController, RootNavigator) {
                let (services, root) = try await Task.detached {
                    try await AppServices.uiTestLaunchConfiguration(
                        environment: environment, arguments: [], reset: reset, applicationSupport: support)
                }.value
                let directory = try #require(root)
                let native = NativeSessionController(
                    applicationSupport: directory, namespace: services.namespace,
                    credentials: services.sessionCredentials())
                let navigator = RootNavigator()
                await UITestSessionFixture.route(native: native, navigator: navigator)
                return (services, directory, native, navigator)
            }
            let (coldServices, root, cold, coldNavigator) = try await prepare(reset: false)
            #expect(coldNavigator.route == .terms)
            let database = try #require(await cold.accounts.activeDatabase())
            let account = try #require(try await AccountRepository(database: database).account())
            let coldTrips = try await TripRepository(database: database).trips().map(\.id).sorted()
            try await OutboxRepository(database: database).enqueue(
                .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])))
            try await UITestSessionFixture.tearDown(native: cold, auth: nil)
            #expect(await cold.controller.presence == .signedOut)
            #expect(await cold.accounts.activeDatabase() == nil)
            #expect(try await coldServices.sessionCredentials().readStoredSession() == nil)
            let (services, reseededRoot, reseeded, navigator) = try await prepare(reset: true)
            #expect(reseededRoot == root)
            #expect(navigator.route == coldNavigator.route)
            let fresh = try #require(await reseeded.accounts.activeDatabase())
            let freshAccount = try #require(try await AccountRepository(database: fresh).account())
            #expect(freshAccount.id == account.id && freshAccount.email == account.email)
            #expect(
                freshAccount.walkthroughSeen == account.walkthroughSeen
                    && freshAccount.hasVerifiedEmail == account.hasVerifiedEmail)
            #expect(try await TripRepository(database: fresh).trips().map(\.id).sorted() == coldTrips)
            #expect(try await OutboxRepository(database: fresh).pending().isEmpty)
            let policy = try #require(
                try await SettingsRepository(database: fresh).settings().first { $0.section == "policies" }
            )
            .value.decode(AccountPolicies.self)
            try await OutboxRepository(database: fresh).enqueue(.policies(version: policy.termsVersion))
            let deadline = ContinuousClock.now + .seconds(2)
            while navigator.route != .today, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(navigator.route == .today)
            try await UITestSessionFixture.tearDown(native: reseeded, auth: nil)
            try await MockSessionSeed.reset(applicationSupport: root, credentials: services.sessionCredentials())
        }
    }
#endif

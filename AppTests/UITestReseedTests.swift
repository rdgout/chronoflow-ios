#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import LocalStore
    import Testing
    import Sync

    @testable import ChronoFlow

    @MainActor @Suite struct UITestReseedTests {
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
            try await UITestSessionFixture.tearDown(native: reseeded, auth: nil)
            try await MockSessionSeed.reset(applicationSupport: root, credentials: services.sessionCredentials())
        }
    }
#endif

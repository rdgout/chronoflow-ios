import AppCore
import Auth
import Foundation
import LocalStore
import Settings
import Sync
import XCTest

@testable import ChronoFlow
@testable import DataAccess

#if DEBUG
    nonisolated final class SeededSessionIntegrationTests: XCTestCase {
        @MainActor
        func testRestoredSessionRefreshesOfflineAndKeepsSyncedCache() async throws {
            try await withSession(environment: ["CF_AUTH_TEST_OFFLINE": "1"]) { _, _, native, _ in
                let awaitedDatabase = await native.accounts.activeDatabase()
                let database = try XCTUnwrap(awaitedDatabase)
                let cachedAccount = try await AccountRepository(database: database).account()
                let before = try XCTUnwrap(cachedAccount)
                XCTAssertNotNil(before.syncedAt)
                let deadline = ContinuousClock.now + .seconds(5)
                var result: SyncResult?
                while result == nil, ContinuousClock.now < deadline {
                    result = try await native.sync?.refreshNow()
                    await Task.yield()
                }
                XCTAssertEqual(result?.state, .offline, "Restore must attach sync and reach the offline source")
                let after = try await AccountRepository(database: database).account()
                XCTAssertEqual(after, before)
                let session = await native.controller.activeSession()
                XCTAssertEqual(session?.session.accountId, before.id)
            }
        }

        @MainActor
        private func withSession(
            environment: [String: String] = [:],
            body: @MainActor (URL, AppServices, NativeSessionController, RootNavigator) async throws -> Void
        ) async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            var environment = environment
            environment["CF_AUTH_TEST_ID"] = UUID().uuidString
            environment["CF_AUTH_TEST_SIGNED_IN"] = "demo"
            environment["CF_AUTH_TEST_WALKTHROUGH_SEEN"] = "1"
            let services = try AppServices(info: [:], testing: true, environment: environment)
            try await Task.detached { try await services.seedSignedIn(applicationSupport: root) }.value
            let credentials = services.sessionCredentials()
            let navigator = RootNavigator()
            let native = NativeSessionController(
                applicationSupport: root, namespace: .mock, credentials: credentials, syncPath: { nil },
                source: { services.makeDataSource(applicationSupport: root, session: $0) },
                signedOut: { navigator.navigate(to: .signIn) })
            do {
                let presence = try await native.controller.restore()
                XCTAssertEqual(presence, .signedIn(accountID: MockScenarioValues.demoID))
                try await body(root, services, native, navigator)
            } catch {
                await native.sync?.stop()
                await native.stopObserving()
                try? await native.accounts.close()
                try? await credentials.delete()
                throw error
            }
            await native.sync?.stop()
            await native.stopObserving()
            try await native.accounts.close()
            try await credentials.delete()
        }
    }
#endif

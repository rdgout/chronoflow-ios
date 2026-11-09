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
        func testSuccessfulDeletionSignsOutWipesCacheAndRoutesToSignInAfterPasswordRetry() async throws {
            try await withSession { _, services, native, navigator in
                let activeSession = await native.controller.activeSession()
                let session = try XCTUnwrap(activeSession)
                let awaitedDatabase = await native.accounts.activeDatabase()
                let database = try XCTUnwrap(awaitedDatabase)
                let mutationPermit = await native.controller.mutationPermit(for: session)
                let permit = try XCTUnwrap(mutationPermit)
                navigator.navigate(to: .settings)
                let pages = SettingsPagesModel(
                    database: database, permit: permit,
                    isCurrent: { await native.controller.activeSession() == session },
                    delete: { try await native.deleteAccount(password: $0, session: session) })
                let editor = SettingsDeleteModel { try await pages.deleteAccount(password: $0) }
                editor.confirmDeletion()
                editor.password = "wrong"
                await editor.submit()
                XCTAssertEqual(editor.errorKey, "The provided password was incorrect.")
                XCTAssertEqual(editor.stage, .password)
                let stillSignedIn = await native.controller.activeSession()
                XCTAssertEqual(stillSignedIn, session)
                editor.password = MockScenarioValues.password
                await editor.submit()
                XCTAssertEqual(editor.stage, .deleted)
                XCTAssertEqual(navigator.route, .signIn)
                let presence = await native.controller.presence
                let activeDatabase = await native.accounts.activeDatabase()
                XCTAssertEqual(presence, .signedOut)
                XCTAssertNil(activeDatabase)
                let stored = try await services.sessionCredentials().readStoredSession()
                XCTAssertNil(stored)
                do {
                    _ = try await AccountRepository(database: database).account()
                    XCTFail("Deleted account's database remained open")
                } catch { XCTAssertEqual(error as? StoreFailure, .closed) }
                try await native.accounts.open(accountID: AccountID(session.session.accountId))
                let awaitedDatabaseAfterReopen = await native.accounts.activeDatabase()
                let reopened = try XCTUnwrap(awaitedDatabaseAfterReopen)
                let account = try await AccountRepository(database: reopened).account()
                XCTAssertNil(account, "Successful deletion must erase local account data")
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

import AppCore
import Foundation
import Testing

@testable import DataAccess

extension DataSourceSelectionTests {
    #if DEBUG
        @Test func cachedFixtureTemplatesRebaseWithoutSharingSeedMutations() throws {
            let now = MockClock().now()
            let first = try MockAppSeed.make(now: now)
            let shifted = try MockAppSeed.make(
                now: now.addingTimeInterval(3 * 24 * 60 * 60), unverified: true, walkthroughSeen: true)
            let firstAccount = try #require(first.accounts[MockScenarioValues.demoID])
            let shiftedAccount = try #require(shifted.accounts[MockScenarioValues.demoID])
            #expect(firstAccount.trips.map(\.planStartUtc) != shiftedAccount.trips.map(\.planStartUtc))
            #expect(firstAccount.snapshot.hasVerifiedEmail && !firstAccount.walkthroughSeen)
            #expect(!shiftedAccount.snapshot.hasVerifiedEmail && shiftedAccount.walkthroughSeen)
            let repeated = try MockAppSeed.make(now: now)
            #expect(repeated.accounts == first.accounts)
            #expect(repeated.signingKey != first.signingKey)
        }

        @Test func defaultAppMockSignsInDemoWithRNSettingsAndTrips() async throws {
            let store = MemoryMockStateStore()
            let source = try appMock(store: store)
            #expect(store.load() == nil)
            let session = try await login(source)
            #expect(session.account.id == MockScenarioValues.demoID)
            #expect(session.account.name == "Demo Traveller")
            #expect(session.account.hasVerifiedEmail)
            #expect(!session.account.walkthroughSeen)
            let snapshot = try await source.fetchAccount()
            #expect(snapshot.settings.sleepAnswered)
            #expect(snapshot.settings.bodyClock["ageBand"] == .string("18_64"))
            #expect(snapshot.settings.preferences["showOptionalItems"] == .bool(true))
            #expect(snapshot.settings.reminders["leadMin"] == .number(15))
            #expect(snapshot.settings.planCredits["credits"] == .number(3))
            #expect(snapshot.settings.policies.acceptedTermsVersion == "2026-10-01")
            #expect(snapshot.readiness["variant"] == .string("ready"))
            #expect(snapshot.security["twoFactorEnabled"] == .bool(false))
            guard case .array(let passkeys) = snapshot.security["passkeys"] else {
                Issue.record("Expected RN demo passkeys")
                return
            }
            #expect(passkeys.compactMap { $0.object?["name"]?.string } == ["iPhone 16", "MacBook Pro"])
            let trips = try await source.fetchTrips()
            #expect(trips.count == 7)
            #expect(
                trips.map { $0.card.to.iata } == [
                    "HND", "JFK", "SYD", "LHR", "DXB", "AMS", "AMS",
                ])
            for trip in trips {
                let detail = try await source.fetchTripDetail(id: trip.card.id)
                #expect(detail.checkState.planInputHash == trip.planInputHash)
                #expect(detail.checkState.marks.isEmpty)
                #expect(!detail.plan.blocks.isEmpty)
            }
            #expect(store.load()?.mail.isEmpty == true)
            #expect(store.load()?.accounts.count == 2)
        }

        @Test(arguments: [false, true])
        func defaultAppMockChallengesTwoFactorAndAcceptsRNProof(recovery: Bool) async throws {
            let source = try appMock()
            guard
                case .twoFactor(let challenge) = try await source.signIn(
                    passwordInput(email: MockScenarioValues.twoFactorEmail))
            else {
                Issue.record("Expected RN two-factor challenge")
                return
            }
            await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
            let session = try await source.completeTwoFactor(
                TwoFactorInput(
                    challengeId: challenge,
                    proof: recovery
                        ? .recoveryCode(MockScenarioValues.recoveryCode) : .code(MockScenarioValues.twoFactorCode)))
            #expect(session.account.id == MockScenarioValues.twoFactorID)
            #expect(session.account.hasVerifiedEmail)
            #expect(try await source.fetchTrips().count == 7)
            let snapshot = try await source.fetchAccount()
            #expect(snapshot.security["twoFactorEnabled"] == .bool(true))
            #expect(snapshot.security["twoFactorConfirmedAt"]?.string != nil)
            #expect(snapshot.security["passkeys"] == .array([]))
        }

        @Test(arguments: [false, true])
        func authAcceptanceScenariosPersistAndStartOfflineBeforeAnyRequest(unverified: Bool) async throws {
            let seed = try MockAppSeed.make(now: MockClock().now(), unverified: unverified, walkthroughSeen: true)
            let store = MemoryMockStateStore()
            let source = MockDataSource(store: store, seed: seed, sleep: { _ in })
            let session = try await login(source)
            #expect(session.account.hasVerifiedEmail == !unverified)
            #expect(session.account.walkthroughSeen)
            let offline = MockDataSource(store: store, offline: true, sleep: { _ in }, bearer: { session.token })
            await #expect(throws: DataFailure.offline) { try await offline.fetchIdentity() }
            await #expect(throws: DataFailure.offline) { try await offline.signOut() }
            await offline.setOffline(false)
            #expect(try await offline.fetchIdentity().hasVerifiedEmail == !unverified)
            try await offline.signOut()
            await #expect(throws: DataFailure.unauthorized(status: 401)) { try await offline.fetchIdentity() }
            #expect(store.load()?.accounts.count == 2)
        }

        @Test func defaultAppMockReseedsEmptyAndOldStatesAndPreservesCurrentChanges() async throws {
            for old in [MockServerState(), try oldShape()] {
                let store = MemoryMockStateStore(old)
                _ = try await login(appMock(store: store))
                #expect(store.load()?.schemaVersion == MockServerState.currentSchemaVersion)
                #expect(store.load()?.accounts.count == 2)
            }
            let store = MemoryMockStateStore()
            let source = try appMock(store: store)
            let session = try await login(source)
            _ = try await source.send(.profile(ProfileChange(name: "Kept", email: MockScenarioValues.demoEmail)))
            _ = try await source.send(.walkthrough)
            let restarted = MockDataSource(store: store, sleep: { _ in }, bearer: { session.token })
            #expect(try await restarted.fetchIdentity().name == "Kept")
            #expect(try await restarted.fetchIdentity().walkthroughSeen)
        }

        @Test func defaultAppMockKeepsRecoveryConsumptionAcrossRestart() async throws {
            let store = MemoryMockStateStore()
            let first = try appMock(store: store)
            guard
                case .twoFactor(let challenge) = try await first.signIn(
                    passwordInput(email: MockScenarioValues.twoFactorEmail))
            else {
                Issue.record("Expected two-factor challenge")
                return
            }
            _ = try await first.completeTwoFactor(
                TwoFactorInput(challengeId: challenge, proof: .recoveryCode(MockScenarioValues.recoveryCode)))
            let restarted = try appMock(store: store)
            guard
                case .twoFactor(let next) = try await restarted.signIn(
                    passwordInput(email: MockScenarioValues.twoFactorEmail))
            else {
                Issue.record("Expected two-factor challenge after restart")
                return
            }
            await #expect(throws: (any Error).self) {
                try await restarted.completeTwoFactor(
                    TwoFactorInput(challengeId: next, proof: .recoveryCode(MockScenarioValues.recoveryCode)))
            }
        }

        @Test(arguments: ["{}", "corrupt", "legacy"])
        func defaultAppMockReseedsIncompatibleFiles(payload: String) async throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("build/mock-reseed-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = FileMockStateStore(applicationSupport: root)
            try FileManager.default.createDirectory(
                at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data(payload.utf8)
            if payload == "legacy" {
                let seed = try MockAppSeed.make(now: MockClock().now())
                var object = try #require(
                    JSONSerialization.jsonObject(with: JSONEncoder().encode(seed)) as? [String: Any])
                object.removeValue(forKey: "schemaVersion")
                data = try JSONSerialization.data(withJSONObject: object)
            }
            try data.write(to: store.url)
            _ = try await login(appMock(store: store))
            #expect(try store.load()?.accounts.count == 2)
        }

        @Test func explicitEmptyAndCustomSeedsBypassAppReseeding() async throws {
            let emptyStore = MemoryMockStateStore()
            let empty = MockDataSource(store: emptyStore, seed: MockServerState(), sleep: { _ in })
            await #expect(throws: (any Error).self) { try await login(empty) }
            #expect(emptyStore.load()?.accounts.isEmpty == true)
            var custom = try scenarioState()
            custom.accounts.removeValue(forKey: twoFactorID)
            let store = MemoryMockStateStore()
            let source = MockDataSource(store: store, seed: custom, sleep: { _ in })
            _ = try await login(source)
            #expect(store.load()?.accounts.count == 1)
            #expect(try await source.fetchTrips().count == 1)
        }

        private func oldShape() throws -> MockServerState {
            var state = try scenarioState()
            state.schemaVersion = 0
            return state
        }

        private func appMock(store: any MockStateStore = MemoryMockStateStore()) throws -> any DataSource {
            let factory = try DataSourceFactory(release: false, testing: false)
            return factory.make {
                MockDataSource(store: store, now: MockClock().now, sleep: { _ in })
            } api: {
                Issue.record("Default app factory must select mock")
                return MockDataSource(seed: MockServerState(), sleep: { _ in })
            }
        }
    #else
        @Test func releaseDefaultMockHasNoDemoSeed() async throws {
            let store = MemoryMockStateStore()
            let source = MockDataSource(store: store, sleep: { _ in })
            await #expect(throws: (any Error).self) { try await login(source) }
            #expect(store.load()?.accounts.isEmpty == true)
        }
    #endif

    @Test func apiFactoryNeverConstructsMockSeed() throws {
        let factory = try DataSourceFactory(setting: "api", release: true, testing: false)
        let source = factory.make {
            Issue.record("API factory must never construct the mock")
            return MockDataSource()
        } api: {
            APIDataSource(client: APIClient(baseURL: factory.baseURL))
        }
        #expect(source is APIDataSource)
    }
}

#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import LocalStore
    import Sync
    import Testing

    struct MockSessionSeedTests {
        @Test(arguments: ["demo", "twofactor"], ["app", "verify", "terms", "walkthrough"])
        func signedInSeedUsesRestorableCredentialsAndAccountGates(account: String, gate: String) async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let environment = [
                "CF_AUTH_TEST_ID": UUID().uuidString, "CF_AUTH_TEST_SIGNED_IN": account,
                "CF_AUTH_TEST_OFFLINE": "1", "CF_AUTH_TEST_WALKTHROUGH_SEEN": gate == "walkthrough" ? "0" : "1",
                "CF_AUTH_TEST_UNVERIFIED": gate == "verify" ? "1" : "0",
                "CF_AUTH_TEST_TERMS_PENDING": gate == "terms" ? "1" : "0",
            ]
            let configuration = try #require(AuthUITestConfiguration(environment: environment))
            let credentials = SeedMemoryCredentials()
            let seed = try MockAppSeed.make(
                now: Date(), unverified: configuration.unverified, walkthroughSeen: configuration.walkthroughSeen,
                termsPending: configuration.termsPending)
            let source = MockDataSource(
                store: FileMockStateStore(applicationSupport: root), seed: seed, delay: { 0 }, sleep: { _ in },
                bearer: { try await credentials.readStoredSession()?.token })
            let input = PasswordSignInInput(
                email: account == "demo" ? MockScenarioValues.demoEmail : MockScenarioValues.twoFactorEmail,
                password: MockScenarioValues.password, deviceID: configuration.id, deviceName: "test")
            try await MockSessionSeed.run(
                applicationSupport: root, namespace: .mock, credentials: credentials, source: source, input: input,
                twoFactorCode: MockScenarioValues.twoFactorCode)
            let stored = try #require(try await credentials.readStoredSession())
            #expect(
                stored.accountId == (account == "demo" ? MockScenarioValues.demoID : MockScenarioValues.twoFactorID))
            let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
            let controller = SessionController(credentials: credentials, accounts: accounts)
            #expect(try await controller.restore() == .signedIn(accountID: stored.accountId))
            let database = try #require(await accounts.activeDatabase())
            var updates = try await AccountReadinessRepository(database: database).values(accountID: stored.accountId)
                .makeAsyncIterator()
            let values = try #require(try await updates.next() ?? nil)
            let expected: Gate =
                gate == "verify" ? .verify : gate == "terms" ? .terms : gate == "walkthrough" ? .walkthrough : .app
            #expect(values.gate == expected)
            #expect(values.hasStoredData == (gate != "verify"))
            let restarted = MockDataSource(
                store: FileMockStateStore(applicationSupport: root), delay: { 0 }, sleep: { _ in },
                bearer: { stored.token })
            #expect(try await restarted.fetchIdentity().id == stored.accountId)
            try await accounts.close()
            await credentials.delete()
            try await MockSessionSeed.run(
                applicationSupport: root, namespace: .mock, credentials: credentials, source: source, input: input,
                twoFactorCode: MockScenarioValues.twoFactorCode)
            #expect(try await credentials.readStoredSession() == nil)
        }

        @Test func reseedRemovesPreviousAccountQueueAndCompletionMarkerAndMatchesColdSeed() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let credentials = SeedMemoryCredentials()
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            func seed(account: String) async throws -> SeedSummary {
                let source = MockDataSource(
                    store: MemoryMockStateStore(), seed: try MockAppSeed.make(now: now, walkthroughSeen: true),
                    delay: { 0 }, sleep: { _ in }, bearer: { try await credentials.readStoredSession()?.token })
                try await MockSessionSeed.run(
                    applicationSupport: root, namespace: .mock, credentials: credentials, source: source,
                    input: PasswordSignInInput(
                        email: account, password: MockScenarioValues.password, deviceID: UUID().uuidString,
                        deviceName: "test"
                    ),
                    twoFactorCode: MockScenarioValues.twoFactorCode)
                let stored = try #require(try await credentials.readStoredSession())
                let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
                let controller = SessionController(credentials: credentials, accounts: accounts)
                _ = try await controller.restore()
                let database = try #require(await accounts.activeDatabase())
                let account = try #require(try await AccountRepository(database: database).account())
                #expect(stored.accountId == account.id)
                let summary = SeedSummary(
                    id: account.id, email: account.email, walkthrough: account.walkthroughSeen,
                    verified: account.hasVerifiedEmail,
                    trips: try await TripRepository(database: database).trips().map(\.id).sorted(),
                    pending: try await OutboxRepository(database: database).pending().count,
                    synced: account.syncedAt != nil)
                try await accounts.close()
                return summary
            }
            let cold = try await seed(account: MockScenarioValues.twoFactorEmail)
            try await MockSessionSeed.reset(applicationSupport: root, credentials: credentials)
            _ = try await seed(account: MockScenarioValues.demoEmail)
            let accounts = SessionAccountDatabase(applicationSupport: root, namespace: .mock)
            let controller = SessionController(credentials: credentials, accounts: accounts)
            _ = try await controller.restore()
            let database = try #require(await accounts.activeDatabase())
            try await OutboxRepository(database: database).enqueue(
                .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])))
            #expect(try await OutboxRepository(database: database).pending().count == 1)
            try await accounts.close()
            try await MockSessionSeed.reset(applicationSupport: root, credentials: credentials)
            #expect(try await credentials.readStoredSession() == nil)
            #expect(!FileManager.default.fileExists(atPath: root.path))
            let reseeded = try await seed(account: MockScenarioValues.twoFactorEmail)
            #expect(reseeded == cold)
            let oldDatabase = root.appending(
                path: "\(StorageNamespace.mock.directoryName)/Accounts/\(MockScenarioValues.demoID)")
            #expect(!FileManager.default.fileExists(atPath: oldDatabase.path))
        }

    }

    private struct SeedSummary: Equatable {
        let id: String
        let email: String
        let walkthrough: Bool
        let verified: Bool
        let trips: [String]
        let pending: Int
        let synced: Bool
    }

    private actor SeedMemoryCredentials: SessionStore {
        private var data: Data?
        func read() -> Data? { data }
        func write(_ data: Data) { self.data = data }
        func delete() { data = nil }
    }
#endif

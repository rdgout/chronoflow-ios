import AppCore
import Foundation
import Testing

@testable import DataAccess

final class FailingMockStore: MockStateStore, @unchecked Sendable {
    let memory = MemoryMockStateStore()
    private let lock = NSLock()
    private var fail = false
    private var events: [String] = []
    func setFail(_ fail: Bool) { lock.withLock { self.fail = fail } }
    func load() throws -> MockServerState? {
        #expect(!Thread.isMainThread)
        lock.withLock { events.append("load") }
        return memory.load()
    }
    func save(_ state: MockServerState) throws {
        #expect(!Thread.isMainThread)
        if lock.withLock({ fail }) { throw DataFailure.server(status: nil) }
        memory.save(state)
    }
    var loads: Int { lock.withLock { events.count } }
}

@Suite struct MockPersistenceTests {
    @Test func lazyLoadOffMainAndSaveFailurePreservesState() async throws {
        let store = FailingMockStore()
        let source = try mockSource(store: store)
        #expect(store.loads == 0)
        _ = try await login(source)
        #expect(store.loads == 1)
        store.setFail(true)
        await #expect(throws: (any Error).self) {
            try await source.send(.profile(ProfileChange(name: "Lost", email: "demo@example.com")))
        }
        store.setFail(false)
        #expect(try await source.fetchIdentity().name == "Demo Traveller")
    }
    @Test func restartPersistsAuthInboxSettingsChecksAndLimits() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "build/mock-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileMockStateStore(applicationSupport: root)
        let clock = MockClock()
        let source = try mockSource(clock: clock, store: store)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let session = try await login(source)
        _ = try await source.send(.walkthrough)
        _ = try await source.send(.settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])))
        try await source.requestPasswordReset(email: "demo@example.com")
        let restarted = try mockSource(clock: clock, store: store, seed: MockServerState(), bearer: { session.token })
        #expect(try await restarted.fetchIdentity().walkthroughSeen)
        #expect(try await restarted.fetchAccount().settings.preferences["timeFormat"] == .string("12"))
        #expect(try await restarted.inbox().count == 1)
        #expect(try await restarted.fetchTrips().count == 1)
        for _ in 0..<4 { _ = try await source.signIn(passwordInput()) }
        let throttledRestart = try mockSource(clock: clock, store: store)
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) {
            try await login(throttledRestart)
        }
        #expect(store.url.path.contains("ChronoFlowMock/Server"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("ChronoFlow/Accounts").path))
    }
    @Test func corruptStateNeverFallsBackToSeed() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
            "build/mock-corrupt-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileMockStateStore(applicationSupport: root)
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: store.url)
        let source = try mockSource(store: store)
        await #expect(throws: (any Error).self) { try await login(source) }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "corrupt")
    }
    @Test func concurrentRegistrationsKeepAllAccounts() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<5 {
                group.addTask { _ = try await source.signUp(registration("new\(index)@example.com")) }
            }
            try await group.waitForAll()
        }
        #expect(try await source.inbox().count == 5)
        clock.advance(60)
        for index in 0..<5 {
            guard
                case .session(let result) = try await source.signIn(
                    passwordInput(email: "new\(index)@example.com", password: newPassword))
            else {
                Issue.record("Expected session")
                return
            }
            #expect(result.account.email == "new\(index)@example.com")
        }
    }
}

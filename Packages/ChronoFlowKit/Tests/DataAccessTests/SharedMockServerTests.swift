import AppCore
import Foundation
import Testing

@testable import DataAccess

struct SharedMockServerTests {
    @Test func cachedSourcesShareMailAndSessionInvalidation() async throws {
        let store = MemoryMockStateStore()
        let first = try mockSource(store: store)
        let session = try await login(first)
        let second = MockDataSource(
            store: store, delay: { 0 }, sleep: { _ in }, bearer: { session.token })
        #expect(try await first.fetchIdentity().id == demoID)
        #expect(try await second.fetchIdentity().id == demoID)
        #expect(try await second.inbox().isEmpty)
        try await first.requestPasswordReset(email: "demo@example.com")
        #expect(try await second.inbox().count == 1)
        try await second.requestPasswordReset(email: "demo@example.com")
        #expect(try await first.inbox().count == 2)
        try await second.signOut()
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await first.fetchIdentity() }
    }

    @Test func concurrentMemoryMutationsRetainEveryMail() async throws {
        let store = MemoryMockStateStore()
        let clock = MockClock()
        let first = try mockSource(clock: clock, store: store)
        _ = try await first.inbox()
        let second = try mockSource(clock: clock, store: store)
        _ = try await second.inbox()
        async let one: Void = first.requestPasswordReset(email: "demo@example.com")
        async let two: Void = second.requestPasswordReset(email: "twofactor@example.com")
        _ = try await (one, two)
        let mail = try await first.inbox()
        #expect(mail.count == 2)
        #expect(try await second.inbox() == mail)
    }
}

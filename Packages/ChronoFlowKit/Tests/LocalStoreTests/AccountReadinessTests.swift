import AppCore
import Foundation
import Testing

@testable import LocalStore

@Suite struct AccountReadinessTests {
    @Test func sqliteMarkerAndGatePrecedenceAreObservedTogether() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: accountA)
        var iterator = try await AccountReadinessRepository(database: database).values(accountID: accountA)
            .makeAsyncIterator()
        #expect(try await iterator.next() == .some(nil))
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: accountA, name: "Test", email: "a@example.test", hasVerifiedEmail: false))
        #expect(try await iterator.next()??.gate == .verify)
        let accounts = AccountRepository(database: database)
        try await accounts.upsert(
            AccountRecord(id: accountA, name: "Test", email: "a@example.test", walkthroughSeen: false))
        #expect(try await iterator.next()??.gate == .walkthrough)
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(
                section: "policies", value: .encoding(AccountPolicies(termsVersion: "2", privacyVersion: "1"))))
        #expect(try await iterator.next()??.gate == .terms)
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(
                section: "policies",
                value: .encoding(AccountPolicies(termsVersion: "2", privacyVersion: "1", acceptedTermsVersion: "2"))))
        #expect(try await iterator.next()??.hasStoredData == false)
        try await accounts.upsert(
            AccountRecord(
                id: accountA, name: "Test", email: "a@example.test", syncedAt: "2026-11-06T00:00:00Z",
                walkthroughSeen: true))
        let ready = try await iterator.next()
        #expect(ready??.gate == .app)
        #expect(ready??.hasStoredData == true)
        try await database.close()
        #expect(try await iterator.next() == nil)
    }
}

import AppCore
import Foundation
import XCTest

@testable import ChronoFlow

nonisolated final class KeychainSessionStoreTests: XCTestCase {
    func testHostedKeychainRoundTripAndMalformedDeletion() async throws {
        let store = KeychainSessionStore(service: "net.chronoflow.app.native.tests.\(UUID().uuidString)")
        do {
            try await store.delete()
            let empty = try await store.read()
            XCTAssertNil(empty)
            let data = try JSONEncoder().encode(StoredSession(token: "test", accountId: "account"))
            try await store.write(data)
            let presence = await store.loadSession()
            XCTAssertEqual(presence, .signedIn(accountID: "account"))
            try await store.write(Data("invalid".utf8))
            let malformed = await store.loadSession()
            XCTAssertEqual(malformed, .signedOut)
            let deleted = try await store.read()
            XCTAssertNil(deleted)
            try await store.delete()
        } catch {
            try? await store.delete()
            throw error
        }
    }
}

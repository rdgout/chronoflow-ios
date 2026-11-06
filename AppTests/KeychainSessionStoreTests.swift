import AppCore
import Foundation
import Security
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
    func testLegacyShapeAccessibilityAndSourceNamespaces() async throws {
        let suffix = ".tests." + UUID().uuidString
        let api = KeychainSessionStore(service: StorageNamespace.api.keychainService + suffix)
        let mock = KeychainSessionStore(service: StorageNamespace.mock.keychainService + suffix)
        do {
            try await api.write(
                Data(#"{"token":"legacy-native","accountId":"019a562b-8000-7000-8000-000000000001"}"#.utf8))
            let legacy = try await api.readStoredSession()
            XCTAssertEqual(legacy?.token, "legacy-native")
            let noMockSession = try await mock.readStoredSession()
            XCTAssertNil(noMockSession)
            try await mock.write(Data(#"{"token":"mock","accountId":"019a562b-8000-7000-8000-000000000002"}"#.utf8))
            let apiSession = try await api.readStoredSession()
            XCTAssertEqual(apiSession?.token, "legacy-native")
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: StorageNamespace.api.keychainService + suffix,
                kSecAttrAccount as String: "session", kSecReturnAttributes as String: true,
            ]
            var attributes: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
            let values = try XCTUnwrap(attributes as? [String: Any])
            XCTAssertEqual(
                values[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            try await api.delete()
            let survives = try await mock.readStoredSession()
            XCTAssertEqual(survives?.token, "mock")
            try await mock.delete()
        } catch {
            try? await api.delete()
            try? await mock.delete()
            throw error
        }
    }

}

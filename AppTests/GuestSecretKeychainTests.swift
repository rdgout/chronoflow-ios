import AppCore
import Foundation
import Security
import XCTest

@testable import ChronoFlow

nonisolated final class GuestSecretKeychainTests: XCTestCase {
    func testGuestSecretsRotateDiscardAndClearWithDeviceOnlyAccessibility() async throws {
        executionTimeAllowance = 60
        let service = StorageNamespace.mock.keychainService + ".tests." + UUID().uuidString
        let session = KeychainSessionStore(service: service)
        let store = KeychainGuestSecretStore(service: service + ".guest-secrets")
        do {
            try await session.write(Data("member-session".utf8))
            try await store.set("old-secret", for: "old")
            try await store.rotate(from: "old", to: "new", secret: "new-secret")
            let old = try await store.get(for: "old")
            let new = try await store.get(for: "new")
            XCTAssertNil(old)
            XCTAssertEqual(new, "new-secret")
            try await store.rotate(from: "new", to: "new", secret: "updated-secret")
            let updated = try await store.get(for: "new")
            XCTAssertEqual(updated, "updated-secret")
            let accessibility = try await Self.accessibility(service: service + ".guest-secrets", token: "new")
            XCTAssertEqual(accessibility, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            try await store.delete(for: "new")
            let discarded = try await store.get(for: "new")
            XCTAssertNil(discarded)
            try await store.set("first-secret", for: "first")
            try await store.set("second-secret", for: "second")
            try await store.deleteAll()
            let first = try await store.get(for: "first")
            let second = try await store.get(for: "second")
            let member = try await session.read()
            XCTAssertNil(first)
            XCTAssertNil(second)
            XCTAssertEqual(member, Data("member-session".utf8))
            try await session.delete()
        } catch {
            try? await store.deleteAll()
            try? await session.delete()
            throw error
        }
    }

    private static func accessibility(service: String, token: String) async throws -> String? {
        try await Task.detached {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: token, kSecReturnAttributes as String: true,
            ]
            var attributes: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &attributes)
            guard status == errSecSuccess else { throw KeychainGuestSecretStore.Failure(status: status) }
            return (attributes as? [String: Any])?[kSecAttrAccessible as String] as? String
        }.value
    }
}

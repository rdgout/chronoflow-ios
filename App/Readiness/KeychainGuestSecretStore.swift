import AppCore
import Foundation
import Security

actor KeychainGuestSecretStore: GuestSecretStore {
    struct Failure: Error { let status: OSStatus }
    let service: String

    init(service: String = "net.chronoflow.app.native.guest-secrets") {
        self.service = service
    }

    init(namespace: StorageNamespace) {
        service = namespace.keychainService + ".guest-secrets"
    }

    private func query(token: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        ]
        if let token { query[kSecAttrAccount as String] = token }
        return query
    }

    func set(_ secret: String, for token: String) throws {
        assert(!Thread.isMainThread)
        let query = query(token: token)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    func get(for token: String) throws -> String? {
        assert(!Thread.isMainThread)
        var lookup = query(token: token)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    func delete(for token: String) throws { try remove(query(token: token)) }

    func rotate(from oldToken: String?, to newToken: String, secret: String) throws {
        try set(secret, for: newToken)
        if let oldToken, oldToken != newToken { try delete(for: oldToken) }
    }

    func deleteAll() throws { try remove(query()) }

    private func remove(_ query: [String: Any]) throws {
        assert(!Thread.isMainThread)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

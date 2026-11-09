import AppCore
import Foundation
import Security

actor KeychainSessionStore: SessionStore {
    struct Failure: Error { let status: OSStatus }
    let service: String
    let account: String

    init(service: String = "net.chronoflow.app.native", account: String = "session") {
        self.service = service
        self.account = account
    }

    init(namespace: StorageNamespace) {
        service = namespace.keychainService
        account = "session"
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> Data? {
        assert(!Thread.isMainThread)
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return item as? Data
    }

    func write(_ data: Data) throws {
        assert(!Thread.isMainThread)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    func delete() throws {
        assert(!Thread.isMainThread)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

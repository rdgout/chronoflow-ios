import Foundation

public protocol GuestSecretStore: Sendable {
    func set(_ secret: String, for token: String) async throws
    func get(for token: String) async throws -> String?
    func delete(for token: String) async throws
    func rotate(from oldToken: String?, to newToken: String, secret: String) async throws
    func deleteAll() async throws
}

public actor MemoryGuestSecretStore: GuestSecretStore {
    private var secrets: [String: String] = [:]

    public init() {}

    public func set(_ secret: String, for token: String) { secrets[token] = secret }
    public func get(for token: String) -> String? { secrets[token] }
    public func delete(for token: String) { secrets[token] = nil }

    public func rotate(from oldToken: String?, to newToken: String, secret: String) {
        set(secret, for: newToken)
        if let oldToken, oldToken != newToken { delete(for: oldToken) }
    }

    public func deleteAll() { secrets.removeAll() }
}

public enum GuestRecoveryLocation {
    public static func file(applicationSupport: URL, namespace: StorageNamespace) -> URL {
        applicationSupport.appendingPathComponent(namespace.directoryName, isDirectory: true)
            .appendingPathComponent("guest-wizard.json")
    }
}

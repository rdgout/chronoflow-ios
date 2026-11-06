import Foundation

public struct StoredSession: Codable, Sendable, Equatable {
    public let token: String
    public let accountId: String

    public init(token: String, accountId: String) {
        self.token = token
        self.accountId = accountId
    }

    public static func parse(_ data: Data) -> Self? {
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
            !value.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !value.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }
}

public protocol SessionStore: Sendable {
    func read() async throws -> Data?
    func write(_ data: Data) async throws
    func delete() async throws
}

extension SessionStore {
    public func readStoredSession() async throws -> StoredSession? {
        guard let data = try await read() else { return nil }
        guard let session = StoredSession.parse(data) else {
            try await delete()
            return nil
        }
        return session
    }

    public func loadSession() async -> SessionPresence {
        do {
            guard let session = try await readStoredSession() else { return .signedOut }
            return .signedIn(accountID: session.accountId)
        } catch { return .signedOut }
    }
}

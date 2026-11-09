import GRDB

public struct OutboxRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "outbox" }

    public var id: String
    public var kind: String
    public var payload: JSONDocument
    public var createdAt: String
    public var attempts: Int
    public var lastError: String?

    public init(
        id: String, kind: String, payload: JSONDocument, createdAt: String, attempts: Int = 0, lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case kind = "kind"
        case payload = "payload"
        case createdAt = "created_at"
        case attempts = "attempts"
        case lastError = "last_error"
    }
}

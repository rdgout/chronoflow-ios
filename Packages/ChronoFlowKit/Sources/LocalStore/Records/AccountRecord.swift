import GRDB

public struct AccountRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "account" }

    public var id: String
    public var name: String
    public var email: String
    public var hasVerifiedEmail: Bool
    public var syncedAt: String?
    public var walkthroughSeen: Bool

    public init(
        id: String, name: String, email: String, hasVerifiedEmail: Bool = true, syncedAt: String? = nil,
        walkthroughSeen: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.hasVerifiedEmail = hasVerifiedEmail
        self.syncedAt = syncedAt
        self.walkthroughSeen = walkthroughSeen
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case name = "name"
        case email = "email"
        case hasVerifiedEmail = "has_verified_email"
        case syncedAt = "synced_at"
        case walkthroughSeen = "walkthrough_seen"
    }
}

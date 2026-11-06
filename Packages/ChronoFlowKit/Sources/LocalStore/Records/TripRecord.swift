import GRDB

public struct TripRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "trips" }

    public var id: String
    public var card: JSONDocument
    public var adaptation: JSONDocument?
    public var form: JSONDocument?
    public var revision: JSONDocument?
    public var currentInputHash: String?
    public var keepOffline: Bool
    public var departureUtc: String
    public var planStartUtc: String?
    public var planStartZone: String?
    public var preparationDays: Int?
    public var planEndUtc: String?
    public var planEndDate: String?
    public var deletedAt: String?
    public var deletedLocally: Bool

    public init(
        id: String, card: JSONDocument, adaptation: JSONDocument? = nil, form: JSONDocument? = nil,
        revision: JSONDocument? = nil, currentInputHash: String? = nil, keepOffline: Bool = false, departureUtc: String,
        planStartUtc: String? = nil, planStartZone: String? = nil, preparationDays: Int? = nil,
        planEndUtc: String? = nil, planEndDate: String? = nil, deletedAt: String? = nil, deletedLocally: Bool = false
    ) {
        self.id = id
        self.card = card
        self.adaptation = adaptation
        self.form = form
        self.revision = revision
        self.currentInputHash = currentInputHash
        self.keepOffline = keepOffline
        self.departureUtc = departureUtc
        self.planStartUtc = planStartUtc
        self.planStartZone = planStartZone
        self.preparationDays = preparationDays
        self.planEndUtc = planEndUtc
        self.planEndDate = planEndDate
        self.deletedAt = deletedAt
        self.deletedLocally = deletedLocally
    }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case card = "card"
        case adaptation = "adaptation"
        case form = "form"
        case revision = "revision"
        case currentInputHash = "current_input_hash"
        case keepOffline = "keep_offline"
        case departureUtc = "departure_utc"
        case planStartUtc = "plan_start_utc"
        case planStartZone = "plan_start_zone"
        case preparationDays = "preparation_days"
        case planEndUtc = "plan_end_utc"
        case planEndDate = "plan_end_date"
        case deletedAt = "deleted_at"
        case deletedLocally = "deleted_locally"
    }
}

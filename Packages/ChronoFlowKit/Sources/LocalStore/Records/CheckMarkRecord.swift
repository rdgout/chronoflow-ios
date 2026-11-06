import GRDB

public struct CheckMarkRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "check_marks" }

    public var tripId: String
    public var inputHash: String
    public var type: String
    public var localDate: String
    public var ordinal: Int
    public var status: String
    public var markedAt: String

    public init(
        tripId: String, inputHash: String, type: String, localDate: String, ordinal: Int, status: String,
        markedAt: String
    ) {
        self.tripId = tripId
        self.inputHash = inputHash
        self.type = type
        self.localDate = localDate
        self.ordinal = ordinal
        self.status = status
        self.markedAt = markedAt
    }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case inputHash = "input_hash"
        case type = "type"
        case localDate = "local_date"
        case ordinal = "ordinal"
        case status = "status"
        case markedAt = "marked_at"
    }
}

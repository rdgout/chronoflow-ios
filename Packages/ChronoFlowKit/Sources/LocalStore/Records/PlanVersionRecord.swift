import AppCore
import GRDB

public struct PlanVersionRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "plan_versions" }

    public var tripId: String
    public var inputHash: String
    public var detail: JSONDocument
    public var receivedAt: String
    public var detailVersion: String?

    public init(
        tripId: String, inputHash: String, detail: JSONDocument, receivedAt: String, detailVersion: String? = nil
    ) {
        self.tripId = tripId
        self.inputHash = inputHash
        self.detail = detail
        self.receivedAt = receivedAt
        self.detailVersion = detailVersion
    }

    public func decodedDetail() throws -> TripDetail {
        try detail.decode(TripDetail.self)
    }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case inputHash = "input_hash"
        case detail = "detail"
        case receivedAt = "received_at"
        case detailVersion = "detail_version"
    }
}

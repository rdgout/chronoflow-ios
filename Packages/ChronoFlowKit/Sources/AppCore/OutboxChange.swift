import Foundation

public struct CheckOffChange: Codable, Sendable, Equatable {
    public var tripID: String
    public var planInputHash: String
    public var type: BlockType
    public var localDate: String
    public var ordinal: Int
    public var status: CheckStatus?
    enum CodingKeys: String, CodingKey {
        case tripID
        case planInputHash = "plan_input_hash"
        case type
        case localDate = "local_date"
        case ordinal
        case status
    }

    public init(
        tripID: String, planInputHash: String, type: BlockType, localDate: String, ordinal: Int, status: CheckStatus?
    ) {
        self.tripID = tripID
        self.planInputHash = planInputHash
        self.type = type
        self.localDate = localDate
        self.ordinal = ordinal
        self.status = status
    }
}

public struct ProfileChange: Codable, Sendable, Equatable {
    public var name: String
    public var email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

public enum OutboxKind: String, Codable, Sendable {
    case checkOff = "check-off"
    case settings
    case completeTrip = "complete-trip"
    case profile
    case dataExport = "data-export"
    case security, walkthrough
}
public enum SettingsSection: String, Codable, Sendable { case bodyClock, preferences, reminders }
public enum OutboxChange: Codable, Sendable, Equatable {
    case checkOff(CheckOffChange)
    case settings(section: SettingsSection, patch: JSONObject)
    case policies(version: String)
    case profile(ProfileChange)
    case walkthrough
    case unsupported(kind: OutboxKind, payload: JSONObject)
}
public enum MutationReceipt: Sendable, Equatable {
    case acknowledged
    case account(AccountSnapshot)
    case identity(AccountIdentity)
    case checks(TripCheckResult)
}

import GRDB

public struct SettingsRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static var databaseTableName: String { "settings" }

    public var section: String
    public var value: JSONDocument

    public init(section: String, value: JSONDocument) {
        self.section = section
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case section = "section"
        case value = "value"
    }
}

import Foundation

public struct AccountID: Sendable, Hashable, Codable {
    public let rawValue: String

    public init(_ value: String) throws {
        guard value.count == 36, let uuid = UUID(uuidString: value) else { throw Failure.invalidUUID }
        rawValue = uuid.uuidString.lowercased()
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public enum Failure: Error { case invalidUUID }
}

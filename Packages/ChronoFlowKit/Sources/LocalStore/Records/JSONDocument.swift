import Foundation
import GRDB

public struct JSONDocument: Sendable, Equatable, Codable, DatabaseValueConvertible {
    public let rawValue: String

    public init(_ value: String) throws {
        _ = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        rawValue = value
    }

    public init(data: Data) throws {
        guard let value = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected UTF-8 JSON"))
        }
        try self.init(value)
    }

    public var data: Data { Data(rawValue.utf8) }

    public var databaseValue: DatabaseValue { rawValue.databaseValue }

    public static func fromDatabaseValue(_ value: DatabaseValue) -> Self? {
        String.fromDatabaseValue(value).flatMap { try? Self($0) }
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: Data(rawValue.utf8))
    }
}

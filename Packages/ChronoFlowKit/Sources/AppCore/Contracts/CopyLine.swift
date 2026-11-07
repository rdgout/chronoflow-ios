import Foundation

public enum CopyArgValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Decimal)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try container.decode(Decimal.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}

public enum CopyArgument: Codable, Sendable, Equatable {
    case standard(CopyArg)
    case caffeine(CaffeineCopyArg)

    private enum CodingKeys: String, CodingKey { case drinks }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.drinks) {
            self = .caffeine(try CaffeineCopyArg(from: decoder))
        } else {
            self = .standard(try CopyArg(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .standard(let value): try value.encode(to: encoder)
        case .caffeine(let value): try value.encode(to: encoder)
        }
    }
}

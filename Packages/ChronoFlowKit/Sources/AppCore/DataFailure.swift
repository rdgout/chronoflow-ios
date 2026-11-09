import Foundation

public struct FieldMessage: Codable, Sendable, Equatable {
    public let key: String
    public let arguments: [String: JSONValue]
    public init(key: String, arguments: [String: JSONValue] = [:]) {
        self.key = key
        self.arguments = arguments
    }
    public var catalogArguments: [JSONValue] { interpolationNames.compactMap { arguments[$0] } }
    private var interpolationNames: [String] {
        arguments.keys.filter { key.contains(":\($0)") || key.contains("{{\($0)}}") }.sorted()
    }
    public var interpolationKey: String {
        let names = interpolationNames
        return names.enumerated().reduce(key) { result, entry in
            let (index, name) = entry
            let type: String
            if case .number(let value) = arguments[name] {
                let number = NSDecimalNumber(decimal: value)
                type = number.decimalValue == Decimal(number.int64Value) ? "lld" : "f"
            } else {
                type = "@"
            }
            let placeholder = names.count == 1 ? "%\(type)" : "%\(index + 1)$\(type)"
            return result.replacingOccurrences(of: ":\(name)", with: placeholder)
                .replacingOccurrences(of: "{{\(name)}}", with: placeholder)
        }
    }

}

public enum DataFailure: Error, Sendable, Equatable {
    case reviewExpired
    case notEnoughCredits
    case saveCapacity
    case profileInvalid(fields: [String: FieldMessage])
    case offline
    case unauthorized(status: Int)
    case emailUnverified(status: Int)
    case validation(fields: [String: FieldMessage], status: Int)
    case throttled(retryAfterSeconds: TimeInterval, status: Int)
    case conflict(status: Int)
    case server(status: Int?)
    case unsupported(OutboxKind)

    public var status: Int? {
        switch self {
        case .unauthorized(let s), .emailUnverified(let s), .conflict(let s): s
        case .validation(_, let s), .throttled(_, let s): s
        case .server(let s): s
        case .reviewExpired, .notEnoughCredits, .saveCapacity, .profileInvalid: 422
        case .offline, .unsupported: nil
        }
    }
}

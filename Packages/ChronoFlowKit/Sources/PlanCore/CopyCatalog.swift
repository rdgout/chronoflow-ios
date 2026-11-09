import AppCore
import Foundation

public struct CopyCatalog: Sendable {
    struct Table: Decodable { var entries: [Entry] }
    struct Entry: Decodable, Sendable {
        var key: String
        var arguments: [String]
        var languages: [String: Translation]
    }
    struct Translation: Decodable, Sendable {
        struct Case: Decodable, Sendable {
            var bound: Double
            var exact: Bool
            var format: String
        }
        var kind: String
        var formats: [String]?
        var cases: [Case]?

        func format(count: Double) -> String {
            if let cases { return cases.first { $0.exact ? count == $0.bound : count >= $0.bound }?.format ?? "" }
            let forms = formats ?? []
            return forms.isEmpty ? "" : forms[count == 1 ? 0 : min(1, forms.count - 1)]
        }
    }
    let entries: [String: Entry]

    public init(data: Data) throws {
        entries = Dictionary(
            uniqueKeysWithValues: try JSONDecoder().decode(Table.self, from: data).entries.map { ($0.key, $0) })
    }

    public static func load() async throws -> CopyCatalog {
        try await Task.detached {
            try CopyCatalog(data: Data(contentsOf: Bundle.module.url(forResource: "PlanCopy", withExtension: "json")!))
        }.value
    }

    public func contains(_ key: String) -> Bool { entries[key] != nil }

    public func text(_ key: String, language: Language, arguments: [String: String] = [:], count: Double = 1) -> String
    {
        guard let entry = entries[key] else { return Self.interpolate(key, arguments: arguments) }
        let translation = entry.languages[language.rawValue] ?? entry.languages["en"]!
        let values = entry.arguments.map { arguments[$0] ?? ($0 == "count" ? String(count) : ":\($0)") }
        return String(format: translation.format(count: count), arguments: values.map { $0 as CVarArg })
    }

    private static func interpolate(_ key: String, arguments: [String: String]) -> String {
        let regex = try! NSRegularExpression(pattern: ":([A-Za-z][A-Za-z0-9_]*)")
        var result = key
        for match in regex.matches(in: key, range: NSRange(key.startIndex..., in: key)).reversed() {
            let name = String(key[Range(match.range(at: 1), in: key)!])
            if let value = arguments[name], let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: value)
            }
        }
        return result
    }
}

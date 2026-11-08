import AppCore
import Foundation

nonisolated public struct PageCopy: Sendable, Equatable {
    public let language: Language
    private let bundle: Bundle

    public init(language: Language) {
        self.language = language
        bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.language == rhs.language }

    public func count(_ key: String, _ count: Int) -> String {
        String(
            format: bundle.localizedString(forKey: key, value: nil, table: "Localizable"),
            locale: Locale(identifier: language == .nl ? "nl_NL" : "en_GB"), arguments: [Int64(count)])
    }

    public func callAsFunction(_ key: String, _ arguments: String...) -> String {
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return arguments.isEmpty ? value : String(format: value, arguments: arguments)
    }
}

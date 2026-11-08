import AppCore
import Foundation

public enum SettingsStrings {
    public static func text(_ key: String, language: Language, _ values: [String: String] = [:], count: Int? = nil)
        -> String
    {
        let bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        var result = bundle.localizedString(forKey: key, value: key, table: "Settings")
        if let count { result = String(format: result, locale: Locale(identifier: language.rawValue), Int64(count)) }
        for (key, value) in values { result = result.replacingOccurrences(of: "{{\(key)}}", with: value) }
        return result
    }
}

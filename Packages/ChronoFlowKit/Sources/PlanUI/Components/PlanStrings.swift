import AppCore
import Foundation

public enum PlanStrings {
    public static func text(_ key: String, language: Language, _ values: [String: String] = [:]) -> String {
        let bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        var result = bundle.localizedString(forKey: key, value: key, table: "Screens")
        for (key, value) in values { result = result.replacingOccurrences(of: "{{\(key)}}", with: value) }
        return result
    }
}

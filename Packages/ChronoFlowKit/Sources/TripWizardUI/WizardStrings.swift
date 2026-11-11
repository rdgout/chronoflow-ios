import AppCore
import Foundation

nonisolated public enum WizardStrings {
    public static func lockout(seconds: Int, locale: Locale) -> String {
        let wait = LockoutWait(seconds: seconds)
        return String(format: text(wait.localizationKey, locale: locale), locale: locale, Int64(wait.count))
    }

    public static func text(_ key: String, locale: Locale, arguments: [String: String] = [:]) -> String {
        let language = locale.language.languageCode?.identifier == "nl" ? "nl" : "en"
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        let singular = bundle.localizedString(forKey: key + "_one", value: nil, table: "Localizable")
        let text =
            arguments["count"] == "1" && singular != key + "_one"
            ? singular : bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return arguments.reduce(text) {
            $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value)
        }
    }
}

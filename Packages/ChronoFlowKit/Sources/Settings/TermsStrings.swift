import AppCore
import Foundation

public enum TermsStrings {
    public static func text(_ key: String, language: Language) -> String {
        let bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return bundle.localizedString(forKey: key, value: key, table: "Terms")
    }
}

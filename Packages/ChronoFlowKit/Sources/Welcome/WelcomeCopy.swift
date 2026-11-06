import Foundation

public enum WelcomeCopy {
    public static func string(_ key: String, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier == "nl" ? "nl" : "en"
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}

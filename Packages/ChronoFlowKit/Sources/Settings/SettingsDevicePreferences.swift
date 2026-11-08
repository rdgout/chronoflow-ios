import Foundation
import Observation

@MainActor @Observable public final class SettingsDevicePreferences {
    public enum Theme: String, CaseIterable, Sendable { case system, light, dark }
    public enum LanguageChoice: String, CaseIterable, Sendable { case system, en, nl }
    public var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "cf.settings.theme") } }
    public var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: "cf.settings.language") } }
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Theme(rawValue: defaults.string(forKey: "cf.settings.theme") ?? "") ?? .system
        language = LanguageChoice(rawValue: defaults.string(forKey: "cf.settings.language") ?? "") ?? .system
    }

    public func resolvedLocale(phone: Locale = .current) -> Locale {
        switch language {
        case .system: Locale(identifier: phone.language.languageCode?.identifier == "nl" ? "nl" : "en")
        case .en: Locale(identifier: "en")
        case .nl: Locale(identifier: "nl")
        }
    }
}

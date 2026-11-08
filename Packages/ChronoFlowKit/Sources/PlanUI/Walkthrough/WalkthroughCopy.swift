import AppCore
import Foundation

nonisolated struct WalkthroughCopy {
    let language: Language

    func callAsFunction(_ key: String, _ values: [String: String] = [:]) -> String {
        let bundle =
            Bundle.module.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        var text = bundle.localizedString(forKey: key, value: nil, table: "Walkthrough")
        for (name, value) in values { text = text.replacingOccurrences(of: "{{\(name)}}", with: value) }
        return text
    }
}

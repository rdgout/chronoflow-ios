import AppCore
import Foundation
import Testing

@testable import PlanUI

@Suite struct WalkthroughCopyTests {
    @Test func everyBoardStringHasPairedRNDutch() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/PlanUI/Resources/Walkthrough.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for (key, entry) in strings {
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]])
            for language in [Language.en, .nl] {
                let unit = try #require(localizations[language.rawValue]?["stringUnit"] as? [String: String])
                #expect(unit["value"]?.isEmpty == false, "\(language) \(key)")
            }
        }
        let copy = WalkthroughCopy(language: .nl)
        #expect(copy("Skip") == "Overslaan")
        #expect(copy("Next") == "Volgende")
        #expect(copy("Done") == "Klaar")
        #expect(copy("{{current}} of {{total}}", ["current": "2", "total": "3"]) == "2 van 3")
        #expect(copy("Your plan on one timeline") == "Je plan op één tijdlijn")
        #expect(copy("Know each step at a glance") == "Herken elke stap in één oogopslag")
        #expect(copy("Tick off what you did") == "Vink af wat je hebt gedaan")
    }
}

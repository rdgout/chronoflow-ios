import Foundation
import Testing
import TripWizardUI

@Suite struct WizardCopyTests {
    @Test func visibleWizardCopyHasEnglishAndDutchTogether() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = root.appending(path: "Sources/TripWizardUI/Resources/Localizable.xcstrings")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(object["strings"] as? [String: [String: Any]])
        for (key, value) in strings {
            let localizations = try #require(value["localizations"] as? [String: [String: [String: String]]])
            if !key.hasSuffix("_one") { #expect(localizations["en"]?["stringUnit"]?["value"] == key) }
            #expect(localizations["en"]?["stringUnit"]?["value"]?.isEmpty == false)
            #expect(localizations["nl"]?["stringUnit"]?["value"]?.isEmpty == false)
        }
        for key in [
            "Where are you flying?", "When is your flight?", "From your last trip",
            "Check the departure and arrival times.", "Where do you fly home to?",
            "Stop in {{airport}} · {{count}} complete night", "What you entered is not saved.",
        ] {
            #expect(strings[key] != nil)
        }
    }

    @Test func runtimeUsesTheSelectedLanguageAndInterpolation() {
        let dutch = Locale(identifier: "nl_NL")
        #expect(WizardStrings.text("Where are you flying?", locale: dutch) == "Waar vlieg je heen?")
        #expect(WizardStrings.text("Time in {{city}}", locale: dutch, arguments: ["city": "Tokio"]) == "Tijd in Tokio")
        #expect(WizardStrings.text("Continue", locale: Locale(identifier: "en_GB")) == "Continue")
        #expect(WizardStrings.text("{{count}} credits", locale: dutch, arguments: ["count": "1"]) == "1 tegoed")
    }
}

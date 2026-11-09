import AppCore
import Foundation
import PlanCore
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

    @Test func blockingPromptAndExclusionWordingUsesTheServerCatalogInBothLanguages() async throws {
        let catalog = try await CopyCatalog.load()
        let formatter = CopyLineFormatter(catalog: catalog)
        for key in [
            "Which age group are you in?",
            "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?",
            "Do you have bipolar disorder?",
            "Do you have an eye disease, or take medicine that makes your eyes sensitive to light?",
            "Are you pregnant or breastfeeding?",
            "Have you been told to avoid caffeine?",
            "Do you have a risk factor for blood clots, such as a past clot or a clotting disorder?",
            "This plan is not available for travellers under 18.",
            "This plan is not available if, in the past 14 days, you have worked night or rotating shifts or had a very irregular sleep schedule.",
        ] {
            #expect(catalog.contains(key))
            let line = CopyLine(key: key, args: [])
            #expect(formatter.format(line, options: CopyFormat(language: .en)) == key)
            #expect(formatter.format(line, options: CopyFormat(language: .nl)) != key)
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

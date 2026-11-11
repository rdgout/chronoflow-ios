import Auth
import Foundation
import Testing

struct AuthCatalogTests {
    @MainActor @Test func guestSignupBoardsHavePairedCopyAndTheServerPasswordPolicy() {
        let english = Locale(identifier: "en_GB")
        let dutch = Locale(identifier: "nl_NL")
        for (key, nl) in [
            ("Save your plan", "Sla je plan op"),
            (
                "Create an account to save it and open it on any device.",
                "Maak een account om het te bewaren en op elk apparaat te openen."
            ),
            ("We couldn't create your account.", "We konden je account niet aanmaken."),
            ("Your account is ready.", "Je account is klaar."),
            ("Try saving again shortly.", "Probeer het opslaan zo opnieuw."),
            ("Your trip needs a new check.", "Je reis moet opnieuw worden gecontroleerd."),
            (
                "Review your trip again before creating your account.",
                "Bekijk je reis opnieuw voordat je je account maakt."
            ),
            ("Review my trip", "Mijn reis bekijken"),
            ("I already have an account", "Ik heb al een account"),
            ("Create account and save", "Account aanmaken en opslaan"),
        ] {
            #expect(AuthCopy.string(key, locale: english) == key)
            #expect(AuthCopy.string(key, locale: dutch) == nl)
        }
        let hint =
            "Use at least 12 characters, with uppercase and lowercase letters, numbers and symbols. Choose a password that has not appeared in a data leak."
        #expect(AuthCopy.string(hint, locale: english) == hint)
        #expect(AuthCopy.string(hint, locale: dutch) != hint)
    }

    @Test func everyRowHasExactApprovedDutchAndNoFixtureOrPendingText() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Sources/Auth/Resources/Localizable.xcstrings"))
        let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(rows.count >= 23)
        for (key, row) in rows {
            let localizations = try #require(row["localizations"] as? [String: [String: [String: String]]])
            #expect(localizations["en"]?["stringUnit"]?["value"] == key)
            for language in ["en", "nl"] {
                let unit = try #require(localizations[language]?["stringUnit"])
                let value = try #require(unit["value"])
                #expect(unit["state"] == "translated" && !value.isEmpty)
                #expect(!value.contains("PENDING") && !value.contains("rick@example.com"))
                for argument in ["%lld", "%@"] {
                    #expect(
                        value.components(separatedBy: argument).count == key.components(separatedBy: argument).count)
                }
            }
        }
    }
}

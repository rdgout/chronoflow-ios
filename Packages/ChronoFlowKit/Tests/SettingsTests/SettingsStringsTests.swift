import AppCore
import Foundation
import Settings
import Testing

@Suite struct SettingsStringsTests {
    @Test func lockoutPluralUnitsInBothLanguages() {
        for (seconds, en, nl) in [
            (1, "1 second", "1 seconde"), (45, "45 seconds", "45 seconden"),
            (60, "1 minute", "1 minuut"), (61, "2 minutes", "2 minuten"),
            (2818, "47 minutes", "47 minuten"), (3600, "1 hour", "1 uur"), (3601, "2 hours", "2 uur"),
        ] {
            for language in [Language.en, .nl] {
                let expected =
                    language == .en
                    ? "Too many attempts. Try again in \(en)."
                    : "Te veel pogingen. Probeer het over \(nl) opnieuw."
                #expect(SettingsStrings.lockout(seconds: seconds, language: language) == expected)
            }
        }
    }

    @Test func pluralsAndDutchComeFromRN() {
        for (key, enOne, enMany, nlOne, nlMany) in [
            ("%lld credits left", "1 credit left", "2 credits left", "Nog 1 tegoed over", "Nog 2 tegoeden over"),
            (
                "%lld to answer", "1 to answer", "2 to answer", "Nog 1 vraag te beantwoorden",
                "Nog 2 vragen te beantwoorden"
            ),
            (
                "Sign out and lose %lld changes?", "Sign out and lose 1 change?", "Sign out and lose 2 changes?",
                "Uitloggen en 1 wijziging kwijtraken?", "Uitloggen en 2 wijzigingen kwijtraken?"
            ),
            (
                "Synced %lld hours ago", "Synced 1 hour ago", "Synced 2 hours ago", "1 uur geleden gesynchroniseerd",
                "2 uur geleden gesynchroniseerd"
            ),
        ] {
            #expect(SettingsStrings.text(key, language: .en, count: 1) == enOne)
            #expect(SettingsStrings.text(key, language: .en, count: 2) == enMany)
            #expect(SettingsStrings.text(key, language: .nl, count: 1) == nlOne)
            #expect(SettingsStrings.text(key, language: .nl, count: 2) == nlMany)
        }
        #expect(SettingsStrings.text("Sign out", language: .nl) == "Uitloggen")
        #expect(SettingsStrings.text("Stay signed in", language: .nl) == "Ingelogd blijven")
        #expect(
            SettingsStrings.text("On, {{minutes}} min ahead · works offline", language: .nl, ["minutes": "30"])
                == "Aan, 30 minuten van tevoren · werkt ook offline")
        #expect(SettingsStrings.text("Off · works offline", language: .nl) == "Uit · werkt ook offline")
    }
}

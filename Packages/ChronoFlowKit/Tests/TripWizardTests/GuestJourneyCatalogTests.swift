import Foundation
import Testing

@Suite struct GuestJourneyCatalogTests {
    @Test func welcomeWizardSignupAndTripCopyStayPaired() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let keys = [
            "Welcome": ["Plan my trip", "Sign in"],
            "TripWizardUI": [
                "On a normal work day.", "Your answers", "Ready to plan", "Make my plan",
                "Your sign-up credits stay unused.", "Paid with {{cost}} of the 3 credits you get when you sign up.",
            ],
            "Auth": ["Save your plan", "Create account and save", "I already have an account"],
            "PlanUI": ["Loading your plan", "Downloading this trip’s plan…"],
        ]
        for (module, expected) in keys {
            let data = try Data(contentsOf: sources.appending(path: "\(module)/Resources/Localizable.xcstrings"))
            let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(catalog["strings"] as? [String: [String: Any]])
            for key in expected {
                let row = try #require(strings[key], "Missing \(module) copy: \(key)")
                let localizations = try #require(row["localizations"] as? [String: [String: [String: String]]])
                #expect(localizations["en"]?["stringUnit"]?["value"] == key)
                let dutch = try #require(localizations["nl"]?["stringUnit"]?["value"])
                #expect(!dutch.isEmpty && dutch != key)
                #expect(localizations["nl"]?["stringUnit"]?["state"] == "translated")
                if key.contains("{{cost}}") { #expect(dutch.contains("{{cost}}")) }
            }
        }
    }
}

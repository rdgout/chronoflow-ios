import Foundation
import Testing

struct AuthCatalogTests {
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
                #expect(value.components(separatedBy: "%lld").count == key.components(separatedBy: "%lld").count)
            }
        }
    }
}

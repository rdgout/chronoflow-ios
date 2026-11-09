import AppCore
import Foundation
import Settings
import Testing

@Suite struct TermsPresentationTests {
    @Test func catalogPairsEveryBoardStringAndRetainsRNDutch() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/Settings/Resources/Terms.xcstrings")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for (key, entry) in strings {
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]])
            for language in [Language.en, .nl] {
                let unit = try #require(localizations[language.rawValue]?["stringUnit"] as? [String: String])
                #expect(unit["value"]?.isEmpty == false, "\(language) \(key)")
                #expect(TermsStrings.text(key, language: language) == unit["value"])
            }
        }
        #expect(TermsStrings.text("Accept and continue", language: .nl) == "Akkoord en verder")
        #expect(TermsStrings.text("We've updated our terms", language: .nl) == "We hebben onze voorwaarden bijgewerkt")
        #expect(TermsStrings.text("Try again", language: .nl) == "Opnieuw proberen")
    }

    @Test func deviceTableIncludesAllInsetsAndScrollableContentBounds() throws {
        struct Profiles: Decodable {
            struct Device: Decodable {
                struct Insets: Decodable { let top, left, bottom, right: Double }
                let alias: String
                let width, height: Double
                let insets: Insets
            }
            let devices: [String: Device]
        }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SnapshotSupport/profiles.json")
        let devices = try JSONDecoder().decode(Profiles.self, from: Data(contentsOf: file)).devices.values
        #expect(Set(devices.map(\.alias)).isSuperset(of: ["se", "17e", "duo", "18promax"]))
        for device in devices {
            let width = CGFloat(device.width)
            let height = CGFloat(device.height)
            for insets in [
                MoonTarget.Insets(
                    top: device.insets.top, left: device.insets.left, bottom: device.insets.bottom,
                    right: device.insets.right),
                .init(top: 7, left: 19, bottom: 11, right: 31),
            ] {
                let geometry = TermsGeometry(size: CGSize(width: width, height: height), insets: insets)
                #expect(geometry.content.minX == insets.left + 16)
                #expect(geometry.content.maxX == width - insets.right - 16)
                #expect(geometry.content.minY == insets.top + 24)
                #expect(geometry.content.maxY == height - insets.bottom - 32)
                #expect(geometry.content.width > 0 && geometry.content.height > 0)
            }
        }
    }
}

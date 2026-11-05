import Foundation
import Testing

struct CatalogTests {
    @Test func everyKeyHasDutchText() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var catalogs: [URL] = []
        for directory in ["App", "Packages/ChronoFlowKit/Sources"] {
            let files = try #require(
                FileManager.default.enumerator(
                    at: root.appending(path: directory),
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            )
            catalogs += files.compactMap { $0 as? URL }.filter { $0.pathExtension == "xcstrings" }
        }
        #expect(catalogs.count >= 3)
        for url in catalogs.sorted(by: { $0.path < $1.path }) {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
            #expect(catalog.sourceLanguage == "en", "\(url.path)")
            for (key, entry) in catalog.strings {
                #expect(entry.localizations?["nl"]?.hasText == true, "Missing nl value for '\(key)' in \(url.path)")
            }
        }
    }
}

private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: Entry]

    struct Entry: Decodable {
        let localizations: [String: Translation]?
    }

    struct Translation: Decodable {
        let stringUnit: StringUnit?
        let variations: [String: [String: Translation]]?

        var hasText: Bool {
            if let stringUnit {
                return !stringUnit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard let variations, !variations.isEmpty else { return false }
            return variations.values.allSatisfy { !$0.isEmpty && $0.values.allSatisfy(\.hasText) }
        }
    }

    struct StringUnit: Decodable {
        let value: String
    }
}

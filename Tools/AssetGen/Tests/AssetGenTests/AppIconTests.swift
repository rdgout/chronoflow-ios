import CoreGraphics
import Foundation
import ImageIO
import Testing
import TokenGenCore

@testable import AssetGenCore

private var root: URL {
    URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

private func image(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

@Test func appIconOutputsAreFreshAndUseTheDesignedMasters() throws {
    let outputs = try appIconOutputs(root: root)
    #expect(outputs.count == 8)
    try writeOutputs(outputs, root: root, check: true)
    let catalog = "App/Assets.xcassets/ChronoFlow.appiconset"
    for appearance in ["default", "dark", "tinted"] {
        let filename = "AppIcon-\(appearance).png"
        let data = try #require(outputs["\(catalog)/\(filename)"])
        #expect(data == (try Data(contentsOf: root.appending(path: "_design/icon/ios/\(filename)"))))
        let raster = try image(data)
        #expect(raster.width == 1024 && raster.height == 1024)
        #expect(raster.alphaInfo == .none || raster.alphaInfo == .noneSkipFirst || raster.alphaInfo == .noneSkipLast)
    }
    let contents =
        try JSONSerialization.jsonObject(with: #require(outputs["\(catalog)/Contents.json"])) as? [String: Any]
    let entries = try #require(contents?["images"] as? [[String: Any]])
    #expect(entries.count == 3)
    #expect(entries[0]["appearances"] == nil)
    for (entry, appearance) in zip(entries.dropFirst(), ["dark", "tinted"]) {
        #expect(entry["appearances"] as? [[String: String]] == [["appearance": "luminosity", "value": appearance]])
    }
    for directory in [catalog, "App/ChronoFlow.icon"] {
        let enumerator = try #require(FileManager.default.enumerator(atPath: root.appending(path: directory).path))
        let files = Set(enumerator.allObjects.compactMap { $0 as? String }.filter { !$0.hasSuffix("Assets") })
        let expected = Set(
            outputs.keys.filter { $0.hasPrefix("\(directory)/") }.map { String($0.dropFirst(directory.count + 1)) })
        #expect(files == expected, "Generated icon directories must not retain obsolete files")
    }
}

@Test func layeredIconPreservesGlassAndHasAnExplicitDarkSky() throws {
    let outputs = try appIconOutputs(root: root)
    let data = try #require(outputs["App/ChronoFlow.icon/icon.json"])
    let document = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any])
    let groups = try #require(document["groups"] as? [[String: Any]])
    let moon = try #require(groups.first?["layers"] as? [[String: Any]])
    let sky = try #require(groups.last?["layers"] as? [[String: Any]])
    #expect(moon[0]["glass"] as? Bool == true)
    #expect(moon[0]["image-name"] as? String == "moon-glass.png")
    #expect(groups[0]["translucency"] as? [String: AnyHashable] == ["enabled": true, "value": 0.4])
    #expect(groups[0]["shadow"] as? [String: AnyHashable] == ["kind": "neutral", "opacity": 0.5])
    #expect(sky[0]["glass"] as? Bool == false)
    #expect(groups[1]["shadow"] as? [String: AnyHashable] == ["kind": "none", "opacity": 0])
    #expect(sky[0]["image-name"] as? String == "background.png")
    #expect(
        sky[0]["image-name-specializations"] as? [[String: String]] == [
            ["appearance": "dark", "value": "background-dark.png"]
        ])
    for name in ["background", "background-dark", "moon-glass"] {
        let raster = try image(#require(outputs["App/ChronoFlow.icon/Assets/\(name).png"]))
        #expect(raster.width == 1024 && raster.height == 1024)
        if name == "moon-glass" {
            #expect(raster.alphaInfo == .premultipliedLast || raster.alphaInfo == .last)
        } else {
            #expect(
                raster.alphaInfo == .none || raster.alphaInfo == .noneSkipFirst || raster.alphaInfo == .noneSkipLast)
        }
    }
    #expect(
        outputs["App/ChronoFlow.icon/Assets/background.png"]
            != outputs["App/ChronoFlow.icon/Assets/background-dark.png"])
}

@Test func layeredIconUsesComposerPlatformSchemaAndValidImageReferences() throws {
    let outputs = try appIconOutputs(root: root)
    let data = try #require(outputs["App/ChronoFlow.icon/icon.json"])
    let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(document["supported-platforms"] as? [String: String] == ["squares": "shared"])
    let groups = try #require(document["groups"] as? [[String: Any]])
    for group in groups {
        let layers = try #require(group["layers"] as? [[String: Any]])
        for layer in layers {
            let imageName = try #require(layer["image-name"] as? String)
            #expect(!imageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(outputs["App/ChronoFlow.icon/Assets/\(imageName)"] != nil)
            if let specializations = layer["image-name-specializations"] as? [[String: String]] {
                for specialization in specializations {
                    let name = try #require(specialization["value"])
                    #expect(outputs["App/ChronoFlow.icon/Assets/\(name)"] != nil)
                }
            }
        }
    }
}

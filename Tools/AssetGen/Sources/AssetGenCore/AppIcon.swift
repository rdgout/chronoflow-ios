import Foundation
import TokenGenCore

public func appIconOutputs(root: URL) throws -> [String: Data] {
    let source = "_design/icon"
    let catalog = "App/Assets.xcassets/ChronoFlow.appiconset"
    let icon = "App/ChronoFlow.icon"
    let starter = root.appending(path: "\(source)/ios26/ChronoFlow.icon")
    guard
        var document = try JSONSerialization.jsonObject(with: Data(contentsOf: starter.appending(path: "icon.json")))
            as? [String: Any],
        var groups = document["groups"] as? [[String: Any]], groups.count == 2,
        var sky = groups[1]["layers"] as? [[String: Any]], sky.count == 1,
        var moon = groups[0]["layers"] as? [[String: Any]], moon.count == 1,
        sky[0]["name"] as? String == "Sky", moon[0]["name"] as? String == "Moon"
    else { throw GenerationError.invalid("App icon starter must contain the designed Moon and Sky groups") }
    sky[0]["image-name"] = "background.png"
    sky[0]["image-name-specializations"] = [
        ["appearance": "dark", "value": "background-dark.png"]
    ]
    groups[1]["layers"] = sky
    moon[0]["image-name"] = "moon-glass.png"
    groups[0]["layers"] = moon
    document["groups"] = groups
    document["supported-platforms"] = ["squares": "shared"]
    guard
        let colors = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appending(path: "\(source)/colors.json"))) as? [String: String],
        let hex = colors["top"], hex.hasPrefix("#"), hex.count == 7
    else { throw GenerationError.invalid("App icon palette must contain the sky top color") }
    let top = hex.dropFirst()
    let channels = try stride(from: 0, to: 6, by: 2).map { offset in
        let start = top.index(top.startIndex, offsetBy: offset)
        let end = top.index(start, offsetBy: 2)
        guard let value = Int(top[start..<end], radix: 16) else {
            throw GenerationError.invalid("Invalid app icon sky color: \(hex)")
        }
        return number(Double(value) / 255)
    }
    document["fill"] = ["solid": "srgb:\(channels.joined(separator: ",")),1"]
    var outputs = ["\(icon)/icon.json": try jsonData(document)]
    var entries: [[String: Any]] = []
    for appearance in ["default", "dark", "tinted"] {
        let filename = "AppIcon-\(appearance).png"
        var entry: [String: Any] = [
            "idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename,
        ]
        if appearance != "default" {
            entry["appearances"] = [["appearance": "luminosity", "value": appearance]]
        }
        entries.append(entry)
        outputs["\(catalog)/\(filename)"] = try Data(contentsOf: root.appending(path: "\(source)/ios/\(filename)"))
    }
    outputs["\(catalog)/Contents.json"] = try jsonData([
        "info": ["author": "xcode", "version": 1], "images": entries,
    ])
    for name in ["background", "background-dark", "moon-glass"] {
        let url =
            name == "background-dark"
            ? root.appending(path: "\(source)/layers/\(name).svg")
            : starter.appending(path: "Assets/\(name).svg")
        outputs["\(icon)/Assets/\(name).png"] = try renderIconLayer(url)
    }
    return outputs
}

private func renderIconLayer(_ url: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["rsvg-convert", "--width", "1024", "--height", "1024", url.path]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, !data.isEmpty else {
        throw GenerationError.invalid("rsvg-convert failed for \(url.lastPathComponent); install librsvg")
    }
    return data
}

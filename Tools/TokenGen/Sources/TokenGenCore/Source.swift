import Foundation

public struct DesignSource {
    public static let names = [
        "sky-top", "sky-mid", "sky-horizon", "sky-title", "sky-copy", "sky-copy-background", "dawn", "dawn-foreground",
        "background", "foreground", "card", "card-foreground", "popover", "popover-foreground",
        "destructive-foreground", "input", "border", "ring",
        "surface-2", "muted", "secondary", "secondary-foreground", "now",
        "cat-sleep", "cat-sleep-fg", "cat-light", "cat-light-fg", "cat-moderate", "cat-moderate-fg",
        "cat-dark", "cat-dark-fg", "cat-caffeine", "cat-caffeine-fg", "cat-travel", "cat-travel-fg",
        "muted-foreground", "primary", "primary-foreground", "accent", "accent-foreground", "destructive", "dawn-text",
    ]
    public let root: URL
    public let tokens: [String: Any]
    public let theme: String

    public init(root: URL) throws {
        self.root = root
        let data = try Data(contentsOf: root.appending(path: "_design/canvas/ds/chronoflow/tokens.json"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let colors = (json["color"] as! [String: Any])["tokens"] as! [[String: Any]]
        tokens = Dictionary(uniqueKeysWithValues: colors.map { ($0["name"] as! String, $0["value"]!) })
        theme = try String(contentsOf: root.appending(path: "_design/canvas/theme.css"), encoding: .utf8)
        for appearance in ["light", "dark"] {
            let blockPattern =
                appearance == "light"
                ? #":root, \[data-theme="light"\] \{([^}]+)\}"# : #"\[data-theme="dark"\] \{([^}]+)\}"#
            guard let block = try captures(blockPattern, in: theme).first else {
                throw GenerationError.invalid("Missing theme.css block: \(appearance)")
            }
            let regex = try NSRegularExpression(pattern: #"--([a-z0-9-]+):\s*([^;]+);"#)
            let values = Dictionary(
                uniqueKeysWithValues: regex.matches(in: block, range: NSRange(block.startIndex..., in: block)).map {
                    (
                        String(block[Range($0.range(at: 1), in: block)!]),
                        String(block[Range($0.range(at: 2), in: block)!])
                    )
                })
            func resolveCSS(_ name: String, seen: Set<String> = []) throws -> String {
                guard !seen.contains(name), let value = values[name] else {
                    throw GenerationError.invalid("Missing or cyclic CSS token: \(name)")
                }
                if value.hasPrefix("var(--") {
                    return try resolveCSS(String(value.dropFirst(6).dropLast()), seen: seen.union([name]))
                }
                return value
            }
            for name in Self.names {
                let css = try resolveCSS(name)
                guard css == (try resolved(name, appearance, visited: [])) else {
                    throw GenerationError.invalid("tokens.json / theme.css disagree: \(name) \(appearance)")
                }
            }
        }
    }

    public static var authDerivedNames: [String] {
        [
            "auth-error-background", "auth-error-border", "auth-shadow", "settings-warning-background",
            "settings-warning-border", "settings-qr-background",
        ]
    }

    public func color(_ name: String, _ appearance: String) throws -> OKLab {
        if name == "settings-warning-background" {
            return try color("card", appearance).mixed(with: color("dawn", appearance), fraction: 0.1)
        }
        if name == "settings-warning-border" {
            let value = try color("dawn", appearance)
            return OKLab(lightness: value.lightness, a: value.a, b: value.b, alpha: 0.4)
        }
        if name == "settings-qr-background" {
            let board = try String(
                contentsOf: root.appending(path: "_design/canvas/Set2FASetup.dc.html"), encoding: .utf8)
            return try OKLab(css: captures(#"background: (oklch\(1 0 0\))"#, in: board)[0])
        }
        if name == "auth-error-background" {
            return try color("card", appearance).mixed(with: color("destructive", appearance), fraction: 0.1)
        }
        if name == "auth-error-border" {
            let value = try color("destructive", appearance)
            return OKLab(lightness: value.lightness, a: value.a, b: value.b, alpha: 0.35)
        }
        if name == "auth-shadow" {
            let data = try Data(contentsOf: root.appending(path: "_design/canvas/ds/chronoflow/tokens.json"))
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let shadow =
                ((json["shadow"] as! [String: Any])["tokens"] as! [[String: Any]])[0]["value"] as! [String: String]
            return try OKLab(css: captures(#"(oklch\([^)]+\))"#, in: shadow[appearance]!)[0])
        }
        return try OKLab(css: resolved(name, appearance, visited: []))
    }

    private func resolved(_ name: String, _ appearance: String, visited: Set<String>) throws -> String {
        guard !visited.contains(name), let token = tokens[name],
            let value = token as? String ?? (token as? [String: String])?[appearance]
        else {
            throw GenerationError.invalid("Missing or cyclic token: \(name), \(appearance)")
        }
        if value.hasPrefix("{") {
            return try resolved(String(value.dropFirst().dropLast()), appearance, visited: visited.union([name]))
        }
        return value
    }

    public func midStop(_ appearance: String) throws -> Double {
        let values = try captures(#"--sky-mid-stop:\s*([\d.]+)%;"#, in: theme)
        let expected = appearance == "light" ? 55.0 : 60.0
        guard values.count == 2, Double(values[appearance == "light" ? 0 : 1]) == expected else {
            throw GenerationError.invalid("theme.css sky-mid-stop differs from plan: expected 55% light / 60% dark")
        }
        return expected / 100
    }

    public func ramp(_ appearance: String) throws -> [RampStop] {
        try skyRamp(
            top: color("sky-top", appearance), mid: color("sky-mid", appearance),
            horizon: color("sky-horizon", appearance), midStop: midStop(appearance))
    }
}

public func captures(_ pattern: String, in text: String) throws -> [String] {
    let regex = try NSRegularExpression(pattern: pattern)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
}

public func number(_ value: Double) -> String {
    String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), value)
}
public func camelCase(_ name: String) -> String {
    let parts = name.split(separator: "-")
    return String(parts[0]) + parts.dropFirst().map { $0.capitalized }.joined()
}

public func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        + Data("\n".utf8)
}

public func formattedSwift(_ source: String, root: URL) throws -> Data {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/xcrun")
    process.arguments = [
        "swift", "format", "format", "--configuration", root.appending(path: ".swift-format").path, "-",
    ]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    input.fileHandleForWriting.write(Data(source.utf8))
    try input.fileHandleForWriting.close()
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw GenerationError.invalid("swift format failed") }
    return result
}

public func writeOutputs(_ outputs: [String: Data], root: URL, check: Bool) throws {
    for path in outputs.keys.sorted() {
        let url = root.appending(path: path)
        if check {
            guard (try? Data(contentsOf: url)) == outputs[path] else {
                throw GenerationError.invalid("Stale generated output: \(path)")
            }
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try outputs[path]!.write(to: url, options: .atomic)
        }
    }
}

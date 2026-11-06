import CoreGraphics
import Foundation
import QuartzCore
import Testing

@testable import TokenGenCore

private var root: URL {
    URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

@Test func welcomeMetricsComeFromTheBoard() throws {
    let code = String(decoding: try welcomeTokens(root: root), as: UTF8.self)
    for (name, value) in [("topPadding", "64"), ("moonSize", "28"), ("cardRadius", "22"), ("buttonHeight", "52")] {
        #expect(code.contains("var \(name): CGFloat { \(value) }"))
    }
    let committed = try Data(
        contentsOf: root.appending(path: "Packages/ChronoFlowKit/Sources/DesignSystem/WelcomeTokens.generated.swift"))
    #expect(committed == Data(code.utf8))
}

@Test func specColorsAndAliases() throws {
    let source = try DesignSource(root: root)
    let hexes = [
        ["#1F285A", "#4D427F", "#EB9666", "#F4F9FF", "#121932", "#F3F7FC", "#E78A45", "#2D1205", "#F3F7FC"],
        ["#06091C", "#221A40", "#AA5830", "#E5ECF6", "#E5ECF6", "#0A0E1F", "#F2AD73", "#101428", "#0A0E1F"],
    ]
    let p3 = [
        [
            [0.1285, 0.1565, 0.3411], [0.2951, 0.2591, 0.4836], [0.8733, 0.6048, 0.4334], [0.9590, 0.9762, 0.9981],
            [0.0746, 0.0960, 0.1879], [0.9554, 0.9692, 0.9867], [0.8543, 0.5599, 0.3258], [0.1627, 0.0756, 0.0303],
            [0.9554, 0.9692, 0.9867],
        ],
        [
            [0.0260, 0.0360, 0.1041], [0.1281, 0.1029, 0.2429], [0.6228, 0.3604, 0.2228], [0.9039, 0.9230, 0.9591],
            [0.9039, 0.9230, 0.9591], [0.0427, 0.0548, 0.1153], [0.9083, 0.6882, 0.4861], [0.0653, 0.0798, 0.1517],
            [0.0427, 0.0548, 0.1153],
        ],
    ]
    for (t, theme) in ["light", "dark"].enumerated() {
        for (i, name) in DesignSource.names.enumerated() {
            let color = try source.color(name, theme)
            #expect(color.rgb(p3: false).hex == hexes[t][i])
            #expect(zip(color.rgb(p3: true).values, p3[t][i]).allSatisfy { abs($0 - $1) <= 1 / 255.0 })
            #expect(color.alpha == (name == "sky-copy-background" ? 0.9 : 1))
        }
    }
}

@Test func perSegmentRampMatchesTrueOKLab() throws {
    let source = try DesignSource(root: root)
    let samples = [
        [
            "#1F285A", "#272D61", "#303167", "#38366E", "#403B75", "#493F7C", "#5D4C7F", "#7E607E", "#A1737A",
            "#C58572", "#EB9666",
        ],
        [
            "#06091C", "#0A0C22", "#0F0F27", "#13112D", "#181434", "#1D173A", "#221A40", "#402B42", "#623B41",
            "#854A3C", "#AA5830",
        ],
    ]
    for (t, theme) in ["light", "dark"].enumerated() {
        let mid = try source.midStop(theme)
        let ramp = try source.ramp(theme)
        let top = try source.color("sky-top", theme)
        let middle = try source.color("sky-mid", theme)
        let end = try source.color("sky-horizon", theme)
        #expect(ramp.contains { $0.location == mid && $0.color == middle.rgb(p3: true) })
        for i in 0...1000 {
            let x = Double(i) / 1000
            let lab =
                x <= mid
                ? top.mixed(with: middle, fraction: x / mid) : middle.mixed(with: end, fraction: (x - mid) / (1 - mid))
            let hi = ramp.firstIndex { $0.location >= x }!
            let lo = max(0, hi - 1)
            let f = hi == lo ? 0 : (x - ramp[lo].location) / (ramp[hi].location - ramp[lo].location)
            let interpolated = ramp[lo].color.mixed(with: ramp[hi].color, fraction: f)
            #expect(zip(interpolated.values, lab.rgb(p3: true).values).allSatisfy { abs($0 - $1) <= 1 / 255.0 })
            if i % 100 == 0 { #expect(lab.rgb(p3: false).hex == samples[t][i / 100]) }
        }
    }
}

@Test func generatedFilesAreCurrentAndLaunchSkyCopiesMatch() throws {
    let outputs = try tokenOutputs(root: root)
    try writeOutputs(outputs, root: root, check: true)
    #expect(
        outputs["App/Assets.xcassets/LaunchSky.colorset/Contents.json"]
            == outputs[
                "Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Colors.xcassets/LaunchSky.colorset/Contents.json"
            ])
}

@Test @MainActor func coreAnimationRampPixelsMatchTrueOKLab() throws {
    let source = try DesignSource(root: root)
    for theme in ["light", "dark"] {
        let stops = try source.ramp(theme)
        let layer = CAGradientLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1001)
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        layer.colors = stops.map {
            CGColor(colorSpace: space, components: $0.color.values.map { CGFloat($0) } + [CGFloat(1)])!
        }
        layer.locations = stops.map { NSNumber(value: $0.location) }
        var bytes = [UInt8](repeating: 0, count: 1001 * 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(
                data: data.baseAddress, width: 1, height: 1001, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: 1001)
            context.scaleBy(x: 1, y: -1)
            layer.render(in: context)
        }
        let top = try source.color("sky-top", theme)
        let mid = try source.color("sky-mid", theme)
        let end = try source.color("sky-horizon", theme)
        let m = try source.midStop(theme)
        var maxError = 0.0
        var worst = ""
        for y in 0..<1001 {
            let x = (Double(y) + 0.5) / 1001
            let trueColor =
                x <= m
                ? top.mixed(with: mid, fraction: x / m).rgb(p3: true)
                : mid.mixed(with: end, fraction: (x - m) / (1 - m)).rgb(p3: true)
            for c in 0..<3 {
                let error = abs(Double(bytes[y * 4 + c]) - (trueColor.values[c] * 255).rounded()) / 255
                if error > maxError {
                    maxError = error
                    worst = "y=\(y) c=\(c) actual=\(bytes[y * 4 + c]) expected=\(trueColor.values[c] * 255)"
                }
            }
        }
        #expect(
            maxError <= 1 / 255.0,
            "Actual CAGradientLayer raster must match OKLab in \(theme), error \(maxError), \(worst)")
    }
}

@Test func staleOutputIsRejected() throws {
    let directory = root.appending(path: "build/TokenGenProbe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputs = ["probe.json": Data("expected".utf8)]
    try writeOutputs(outputs, root: directory, check: false)
    try Data("stale".utf8).write(to: directory.appending(path: "probe.json"))
    #expect(throws: GenerationError.self) { try writeOutputs(outputs, root: directory, check: true) }
}

@Test func conflictingDesignSourcesAreRejected() throws {
    let directory = root.appending(path: "build/TokenGenSourceProbe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let tokenPath = "_design/canvas/ds/chronoflow/tokens.json"
    let themePath = "_design/canvas/theme.css"
    try FileManager.default.createDirectory(
        at: directory.appending(path: tokenPath).deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: root.appending(path: tokenPath), to: directory.appending(path: tokenPath))
    let theme = try String(contentsOf: root.appending(path: themePath), encoding: .utf8)
    try theme.replacingOccurrences(of: "--dawn: oklch(0.72 0.14 55)", with: "--dawn: oklch(0.73 0.14 55)")
        .write(to: directory.appending(path: themePath), atomically: true, encoding: .utf8)
    #expect(throws: GenerationError.self) { try DesignSource(root: directory) }
}

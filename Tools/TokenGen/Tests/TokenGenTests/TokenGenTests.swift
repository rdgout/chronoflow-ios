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
        for (i, name) in DesignSource.names.prefix(9).enumerated() {
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

@Test func authMixUsesOKLabAndPreservesBothAppearances() throws {
    let source = try DesignSource(root: root)
    func contrast(_ a: OKLab, _ b: OKLab) -> Double {
        func luminance(_ color: OKLab) -> Double {
            let channels = color.rgb(p3: false).values.map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        let first = luminance(a)
        let second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
    for theme in ["light", "dark"] {
        for (text, background) in [
            ("card-foreground", "card"), ("card-foreground", "auth-error-background"),
            ("muted-foreground", "card"), ("primary-foreground", "primary"), ("dawn-text", "card"),
            ("destructive", "card"), ("foreground", "card"), ("foreground", "background"),
        ] {
            let ratio = try contrast(source.color(text, theme), source.color(background, theme))
            print("Auth contrast \(theme): \(text) / \(background) = \(ratio):1")
            #expect(
                ratio >= 4.5,
                "\(text) on \(background), \(theme)")
        }
        for (border, background) in [("input", "card"), ("input", "background"), ("border", "card")] {
            let ratio = try contrast(source.color(border, theme), source.color(background, theme))
            print(
                "Auth board contrast accepted, OQ 33 (user 2026-11-06), \(theme): \(border) / \(background) = \(ratio):1"
            )
            #expect(ratio < 3, "Re-review contrast accepted, OQ 33 (user 2026-11-06), when board borders change")
        }
        let mixed = try source.color("auth-error-background", theme)
        let expected = try source.color("card", theme).mixed(with: source.color("destructive", theme), fraction: 0.1)
        #expect(mixed.rgb(p3: true) == expected.rgb(p3: true))
        #expect(try source.color("auth-error-border", theme).alpha == 0.35)
        #expect(try source.color("card", theme).rgb(p3: true) != source.color("card-foreground", theme).rgb(p3: true))
    }
    #expect(
        try authTokens(root: root)
            == Data(
                contentsOf: root.appending(
                    path: "Packages/ChronoFlowKit/Sources/DesignSystem/AuthTokens.generated.swift")))
}

@Test func authGuestFooterExceptionStillMatchesTheBoardPairAndTypography() throws {
    let board = try String(contentsOf: root.appending(path: "_design/canvas/AuthSignIn.dc.html"), encoding: .utf8)
    let footer = try captures(#"<a href="GuestFlight.dc.html" style="([^"]+)""#, in: board)
    #expect(footer.count == 1)
    let style = try #require(footer.first)
    for declaration in [
        "background: var(--sky-copy-background)", "color: var(--sky-copy)",
        "font-size: 14px", "line-height: 20px", "font-weight: 500",
    ] {
        #expect(
            style.contains(declaration),
            "Re-review sign-in.guest contrast accepted, OQ 33 (user 2026-11-06), when its design changes")
    }
}

@Test func authSourceChangesCannotHideBehindUnrelatedDeclarations() throws {
    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
    let board = try read("_design/canvas/AuthSignIn.dc.html")
    let bundle = try read("_design/canvas/ds/chronoflow/components/bundle.js")
    let css = try read("_design/canvas/ds/chronoflow/components/bundle.css")
    let json =
        try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appending(path: "_design/canvas/ds/chronoflow/tokens.json"))) as! [String: Any]
    let original = try authTokens(root: root, board: board, bundle: bundle, css: css, json: json)
    for (source, before, after) in [
        ("board", "column; gap: 8px; margin-top: 32px", "column; gap: 10px; margin-top: 32px"),
        ("board", "space-between; gap: 8px", "space-between; gap: 10px"),
        ("board", "space-between; height: 44px", "space-between; height: 46px"),
        ("board", "width: 44px; height: 44px", "width: 46px; height: 44px"),
        ("board", "gap: 6px; font-family", "gap: 7px; font-family"),
        ("board", "width=\"16\" height=\"16\"", "width=\"17\" height=\"16\""),
        ("board", "padding: 20px; border-radius: 26px", "padding: 21px; border-radius: 26px"),
        ("board", "margin-top: 1px; color", "margin-top: 3px; color"),
        ("board", "font-size: 18px; line-height: 24px", "font-size: 19px; line-height: 24px"),
        ("board", "font-size: 36px; line-height: 40px", "font-size: 38px; line-height: 40px"),
        ("board", "font-size: 16px; line-height: 24px", "font-size: 17px; line-height: 24px"),
        (
            "board", "font-size: 14px; line-height: 20px; font-weight: 500",
            "font-size: 14px; line-height: 22px; font-weight: 500"
        ),
        ("board", "font-weight: 600; color: var(--dawn-text)", "font-weight: 700; color: var(--dawn-text)"),
        ("board", "font-size: 12px; line-height: 16px", "font-size: 13px; line-height: 16px"),
        ("board", "letter-spacing: -0.01em", "letter-spacing: -0.02em"),
        (
            "board", "font-family: var(--font-display); font-weight: 400",
            "font-family: var(--font-display); font-weight: 500"
        ),
        ("board", "font-family: var(--font-sans)", "font-family: var(--font-display)"),
        ("bundle", "focus-visible:ring-2 focus-visible:ring-ring", "focus-visible:ring-3 focus-visible:ring-ring"),
        ("bundle", "mt-0.5 size-4 shrink-0", "mt-1 size-4 shrink-0"),
        ("bundle", "disabled:opacity-50", "disabled:opacity-40"),
        (
            "bundle", "flex items-center gap-1.5 text-sm text-destructive",
            "flex items-center gap-2 text-sm text-destructive"
        ),
        ("css", "--font-weight-normal:400", "--font-weight-normal:500"),
    ] {
        let input = source == "board" ? board : source == "bundle" ? bundle : css
        #expect(input.contains(before), "Mutation must change its source: \(before)")
        let changed = input.replacingOccurrences(of: before, with: after)
        do {
            let output = try authTokens(
                root: root, board: source == "board" ? changed : board,
                bundle: source == "bundle" ? changed : bundle, css: source == "css" ? changed : css, json: json)
            #expect(output != original, "Undetected auth drift: \(before)")
        } catch is GenerationError {
        }
    }
    for (before, after) in [("'Figtree',", "'OtherSans',"), ("'Fraunces',", "'OtherDisplay',")] {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)
        let changed =
            try JSONSerialization.jsonObject(
                with: Data(text.replacingOccurrences(of: before, with: after).utf8)) as! [String: Any]
        #expect(throws: GenerationError.self) {
            try authTokens(root: root, board: board, bundle: bundle, css: css, json: changed)
        }
    }
}

@Test func wizardExclusionSurfacesUseTheBoardsOKLabMixInBothAppearances() throws {
    let source = try DesignSource(root: root)
    for appearance in ["light", "dark"] {
        let dawn = try source.color("dawn", appearance)
        let expected = try source.color("card", appearance).mixed(with: dawn, fraction: 0.1)
        let background = try source.color("wizard-notice-background", appearance)
        let border = try source.color("wizard-notice-border", appearance)
        #expect(background.rgb(p3: true) == expected.rgb(p3: true))
        #expect(border.rgb(p3: true) == dawn.rgb(p3: true) && border.alpha == 0.4)
    }
}

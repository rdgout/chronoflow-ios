import Foundation
import TokenGenCore

public func assetOutputs(root: URL) throws -> [String: Data] {
    let source = try DesignSource(root: root)
    let board = try String(contentsOf: root.appending(path: "_design/canvas/SplashScreen.dc.html"), encoding: .utf8)
    let moon = try MoonGeometry(board: board)
    guard board.contains("stroke-width=\"1.6\""),
        board.contains("drop-shadow(0 0 18px"), board.contains("var(--dawn) 45%")
    else {
        throw GenerationError.invalid("Moon source differs from plan")
    }
    let app = "App/Assets.xcassets"
    let package = "Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Launch.xcassets"
    let info: [String: Any] = ["author": "xcode", "version": 1]
    var outputs = ["\(package)/Contents.json": try jsonData(["info": info])]
    for name in ["LaunchMoon", "LaunchWordmark"] {
        var entries: [[String: Any]] = []
        for appearance in ["light", "dark"] {
            let color = try source.color(name == "LaunchMoon" ? "dawn" : "sky-title", appearance).rgb(p3: true)
            for scale in [2, 3] {
                let filename = "\(name)-\(appearance)@\(scale)x.png"
                var entry: [String: Any] = ["idiom": "universal", "scale": "\(scale)x", "filename": filename]
                if appearance == "dark" { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
                entries.append(entry)
                let image =
                    name == "LaunchMoon"
                    ? moonImage(color: color, scale: scale, geometry: moon)
                    : try wordmarkImage(layout: WordmarkLayout(root: root, color: color), scale: scale)
                let data = png(image)
                for catalog in [app, package] { outputs["\(catalog)/\(name).imageset/\(filename)"] = data }
            }
            if name == "LaunchMoon" {
                let svg = """
                    <svg xmlns="http://www.w3.org/2000/svg" width="288" height="288" viewBox="0 0 288 288">
                      <defs><filter id="glow" x="-100%" y="-100%" width="300%" height="300%" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="9"/></filter></defs>
                      <g fill="none" stroke="color(display-p3 \(color.values.map(number).joined(separator: " ")))" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
                        <g opacity="0.45" filter="url(#glow)"><path transform="translate(92 92) scale(4.3333333333)" d="\(moon.svgPath)"/></g>
                        <path transform="translate(92 92) scale(4.3333333333)" d="\(moon.svgPath)"/>
                      </g>
                    </svg>

                    """
                outputs["Assets/moon/launch-moon-\(appearance).svg"] = Data(svg.utf8)
            }
        }
        let contents = try jsonData(["info": info, "images": entries])
        for catalog in [app, package] { outputs["\(catalog)/\(name).imageset/Contents.json"] = contents }
    }
    outputs["Packages/ChronoFlowKit/Sources/DesignSystem/MoonGlyph.generated.swift"] = try formattedSwift(
        moon.swiftSource, root: root)
    return outputs
}

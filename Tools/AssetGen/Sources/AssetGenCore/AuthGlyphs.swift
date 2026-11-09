import Foundation
import TokenGenCore

public func authGlyphOutputs(root: URL) throws -> [String: Data] {
    let signIn = try String(contentsOf: root.appending(path: "_design/canvas/AuthSignIn.dc.html"), encoding: .utf8)
    let signUp = try String(contentsOf: root.appending(path: "_design/canvas/AuthSignUp.dc.html"), encoding: .utf8)
    let twoFactor = try String(
        contentsOf: root.appending(path: "_design/canvas/AuthTwoFactor.dc.html"), encoding: .utf8)
    let bundle = try String(
        contentsOf: root.appending(path: "_design/canvas/ds/chronoflow/components/bundle.js"), encoding: .utf8)
    let svgs = try captures(#"(<svg\b[^>]*>[\s\S]*?</svg>)"#, in: signIn + signUp + twoFactor)
    let catalog = "Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Auth.xcassets"
    let info: [String: Any] = ["author": "xcode", "version": 1]
    var outputs = ["\(catalog)/Contents.json": try jsonData(["info": info])]
    for (name, marker) in [
        ("AuthBack", "m15 18-6-6 6-6"), ("AuthEye", "M2.062"),
        ("AuthAlert", "<circle cx=\"12\" cy=\"12\" r=\"10\""),
        ("AuthCheck", "M20 6 9 17l-5-5"), ("AuthKey", "M2.586 17.414"),
    ] {
        guard let svg = svgs.first(where: { $0.contains(marker) }) else {
            throw GenerationError.invalid("Missing auth glyph: \(name)")
        }
        let shapes = String(svg[svg.firstIndex(of: ">")!...].dropFirst().dropLast(6))
        let stroke = try captures(#"stroke-width="([^"]+)""#, in: svg)[0]
        let image =
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"black\" stroke-width=\"\(stroke)\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(shapes)</svg>\n"
        outputs["\(catalog)/\(name).imageset/\(name).svg"] = Data(
            image.replacingOccurrences(of: "currentColor", with: "black").utf8)
        outputs["\(catalog)/\(name).imageset/Contents.json"] = try jsonData([
            "info": info, "images": [["idiom": "universal", "filename": "\(name).svg"]],
            "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
        ])
    }
    // The info glyph is defined in the bundled Lucide component rather than an inline board SVG.
    guard bundle.contains(#"["circle",{cx:"12",cy:"12",r:"10""#),
        bundle.contains(#"["path",{d:"M12 16v-4""#), bundle.contains(#"["path",{d:"M12 8h.01""#)
    else { throw GenerationError.invalid("Info glyph changed") }
    let infoSVG =
        #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>"#
    outputs["\(catalog)/AuthInfo.imageset/AuthInfo.svg"] = Data((infoSVG + "\n").utf8)
    outputs["\(catalog)/AuthInfo.imageset/Contents.json"] = try jsonData([
        "info": info, "images": [["idiom": "universal", "filename": "AuthInfo.svg"]],
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ])
    return outputs
}

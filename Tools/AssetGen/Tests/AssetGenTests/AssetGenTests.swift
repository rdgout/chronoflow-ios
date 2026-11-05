import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import TokenGenCore

@testable import AssetGenCore

private var root: URL {
    URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

private func decode(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { data in
        let context = CGContext(
            data: data.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}

private func alphaCoverage(_ image: CGImage) -> Int {
    let bytes = pixels(image)
    return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) }
}

private func unsmoothedWordmark(layout: WordmarkLayout, scale: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: layout.width * scale, height: layout.height * scale, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setAllowsFontSmoothing(false)
    context.setShouldSmoothFonts(false)
    context.setShouldSubpixelPositionFonts(true)
    context.setShouldSubpixelQuantizeFonts(false)
    context.textPosition = layout.origin
    CTLineDraw(layout.line, context)
    return context.makeImage()!
}

@Test func assetDimensionsP3ColorsAndCopies() throws {
    let outputs = try assetOutputs(root: root)
    try writeOutputs(outputs, root: root, check: true)
    let source = try DesignSource(root: root)
    for theme in ["light", "dark"] {
        for scale in [2, 3] {
            for name in ["LaunchMoon", "LaunchWordmark"] {
                let suffix = "\(name).imageset/\(name)-\(theme)@\(scale)x.png"
                let data = try #require(outputs["App/Assets.xcassets/\(suffix)"])
                #expect(
                    data == outputs["Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Launch.xcassets/\(suffix)"])
                let image = try decode(data)
                #expect(image.colorSpace?.name == CGColorSpace.displayP3)
                if name == "LaunchMoon" {
                    #expect(image.width == 288 * scale)
                    #expect(image.height == 288 * scale)
                    let bytes = pixels(image)
                    let offset = (92.0 + (12 - 9 / sqrt(2)) * 104 / 24) * Double(scale)
                    let index = (Int(offset) * image.width + Int(offset)) * 4
                    #expect(bytes[index + 3] >= 250, "Outer top-left arc must be solid")
                    let expected = try source.color("dawn", theme).rgb(p3: true)
                    for channel in 0..<3 {
                        #expect(
                            abs(Double(bytes[index + channel]) / Double(bytes[index + 3]) - expected.values[channel])
                                <= 2 / 255.0)
                    }
                    #expect(bytes[3] == 0)
                    let innerX = Int((92 + (16.5 - hypot(9, 9) / 2) * 104 / 24) * Double(scale))
                    let innerY = Int((92 + 7.5 * 104 / 24) * Double(scale))
                    #expect(
                        bytes[(innerY * image.width + innerX) * 4 + 3] >= 250,
                        "SVG coordinates must retain the upper-right opening")
                    let context = CGContext(
                        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.displayP3)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.setFillColor(p3Color(try source.color("sky-top", theme).rgb(p3: true)))
                    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                    context.fill(rect)
                    context.draw(image, in: rect)
                    try png(context.makeImage()!).write(
                        to: root.appending(path: "build/moon-preview-\(theme)-\(scale).png"))
                } else {
                    let layout = try WordmarkLayout(root: root, color: source.color("sky-title", theme).rgb(p3: true))
                    #expect(image.width == layout.width * scale)
                    #expect(image.height == 40 * scale)
                    #expect(abs(layout.origin.x + layout.advance / 2 - CGFloat(layout.width) / 2) < 0.01)
                    #expect(layout.ink.minX >= 0 && layout.ink.maxX <= CGFloat(layout.width))
                    let referenceCoverage = alphaCoverage(unsmoothedWordmark(layout: layout, scale: scale))
                    #expect(referenceCoverage > 0)
                    #expect(alphaCoverage(image) == referenceCoverage, "Baked weight must match unsmoothed iOS text")
                    let bytes = pixels(image)
                    var xs: [Int] = []
                    var ys: [Int] = []
                    for y in 0..<image.height {
                        for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > 127 {
                            xs.append(x)
                            ys.append(y)
                        }
                    }
                    let ink = try #require(xs.min()).double...Double(try #require(xs.max()) + 1)
                    #expect(abs(ink.lowerBound - layout.ink.minX * Double(scale)) <= 1.5)
                    #expect(abs(ink.upperBound - layout.ink.maxX * Double(scale)) <= 1.5)
                    let yMin = Double(try #require(ys.min()))
                    let yMax = Double(try #require(ys.max()) + 1)
                    #expect(abs(yMin - (Double(layout.height) - layout.ink.maxY) * Double(scale)) <= 1.5)
                    #expect(abs(yMax - (Double(layout.height) - layout.ink.minY) * Double(scale)) <= 1.5)
                }
            }
        }
    }
}

extension Int { fileprivate var double: Double { Double(self) } }

@Test func launchPaletteAllowsSRGBCompilationWithinOneByte() throws {
    let source = try DesignSource(root: root)
    let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    for theme in ["light", "dark"] {
        for token in ["dawn", "sky-title"] {
            let original = p3Color(try source.color(token, theme).rgb(p3: true))
            let converted = try #require(original.converted(to: srgb, intent: .relativeColorimetric, options: nil))
            let components = try #require(converted.components).map { ($0 * 255).rounded() / 255 }
            let quantized = try #require(CGColor(colorSpace: srgb, components: components))
            let roundTrip = try #require(quantized.converted(to: p3, intent: .relativeColorimetric, options: nil))
            for (expected, actual) in zip(try #require(original.components), try #require(roundTrip.components)) {
                #expect(abs(expected - actual) <= 1 / 255.0, "Revisit the sRGB exception if launch colors change")
            }
        }
    }
}

@Test func moonGeometryComesFromTheBoardForBothRenderers() throws {
    let board = try String(contentsOf: root.appending(path: "_design/canvas/SplashScreen.dc.html"), encoding: .utf8)
    let moon = try MoonGeometry(board: board)
    #expect(moon.viewBox == 24)
    #expect(moon.start == CGPoint(x: 12, y: 3))
    #expect(moon.arcs.count == 2)
    let inner = moon.arcs[0]
    #expect(abs(inner.center.x - 16.5) < 1e-8 && abs(inner.center.y - 7.5) < 1e-8)
    #expect(abs(inner.radius - hypot(9, 9) / 2) < 1e-8)
    #expect(inner.clockwise && abs(inner.endAngle - inner.startAngle + .pi) < 1e-8)
    let outer = moon.arcs[1]
    #expect(abs(outer.center.x - 12) < 1e-8 && abs(outer.center.y - 12) < 1e-8)
    #expect(outer.radius == 9)
    #expect(!outer.clockwise && abs(outer.endAngle - outer.startAngle - 1.5 * .pi) < 1e-8)

    let shifted = try MoonGeometry(board: board.replacingOccurrences(of: "M12 3", with: "M13 3"))
    #expect(shifted.start.x == moon.start.x + 1)
    for (original, translated) in zip(moon.arcs, shifted.arcs) {
        #expect(abs(translated.center.x - original.center.x - 1) < 1e-8)
        #expect(abs(translated.center.y - original.center.y) < 1e-8)
    }
    #expect(moon.swiftSource != shifted.swiftSource)
    let color = try DesignSource(root: root).color("dawn", "light").rgb(p3: true)
    #expect(
        png(moonImage(color: color, scale: 2, geometry: moon))
            != png(moonImage(color: color, scale: 2, geometry: shifted)))
    #expect(throws: GenerationError.self) { try MoonGeometry(svgPath: "M12 3a6 7 0 0 0 9 9Z") }
    #expect(throws: GenerationError.self) { try MoonGeometry(svgPath: "M12 3L21 12Z") }
}

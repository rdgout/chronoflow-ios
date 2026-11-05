import Accelerate
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import TokenGenCore
import UniformTypeIdentifiers

public func moonPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 12, y: 3))
    path.addArc(
        center: CGPoint(x: 16.5, y: 7.5), radius: hypot(9, 9) / 2, startAngle: -.pi * 3 / 4, endAngle: -.pi * 7 / 4,
        clockwise: true)
    path.addArc(center: CGPoint(x: 12, y: 12), radius: 9, startAngle: 0, endAngle: .pi * 3 / 2, clockwise: false)
    path.closeSubpath()
    return path
}

public struct WordmarkLayout {
    public let line: CTLine
    public let width: Int
    public let height: Int
    public let advance: CGFloat
    public let origin: CGPoint
    public let ink: CGRect

    public init(root: URL, color: RGB) throws {
        let board = try String(contentsOf: root.appending(path: "_design/canvas/SplashScreen.dc.html"), encoding: .utf8)
        let style = try captures(#"word: '([^']+)'"#, in: board)[0]
        let size = Double(try captures(#"font-size: ([\d.]+)px"#, in: style)[0])!
        let lineHeight = Double(try captures(#"line-height: ([\d.]+)px"#, in: style)[0])!
        let tracking = Double(try captures(#"letter-spacing: (-?[\d.]+)em"#, in: style)[0])! * size
        guard size == 32, lineHeight == 40, tracking == -0.32 else {
            throw GenerationError.invalid("Splash wordmark differs from D8")
        }
        let url = root.appending(
            path: "Packages/ChronoFlowKit/Sources/DesignSystem/Resources/Fonts/CFFraunces-400-Opsz32.ttf")
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let descriptor = descriptors.first
        else { throw GenerationError.invalid("Run make fonts before make assets") }
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): p3Color(color),
        ]
        line = CTLineCreateWithAttributedString(NSAttributedString(string: "ChronoFlow", attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let bounds = CTLineGetImageBounds(line, nil)
        let overhang = max(0, -bounds.minX, bounds.maxX - advance)
        width = Int(ceil(advance + 2 * overhang))
        height = Int(lineHeight)
        origin = CGPoint(x: (CGFloat(width) - advance) / 2, y: (lineHeight - ascent - descent) / 2 + descent)
        ink = bounds.offsetBy(dx: origin.x, dy: origin.y)
    }
}

public func p3Color(_ color: RGB) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, components: color.values.map { CGFloat($0) } + [1])!
}

public func wordmarkImage(layout: WordmarkLayout, scale: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: layout.width * scale, height: layout.height * scale, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    // macOS stem darkening would bake a heavier weight than iOS text rendering.
    context.setAllowsFontSmoothing(false)
    context.setShouldSmoothFonts(false)
    context.setShouldSubpixelPositionFonts(true)
    context.setShouldSubpixelQuantizeFonts(false)
    context.textPosition = layout.origin
    CTLineDraw(layout.line, context)
    return context.makeImage()!
}

public func moonImage(color: RGB, scale: Int) -> CGImage {
    let size = 288 * scale
    let count = size * size
    var alpha = [UInt8](repeating: 0, count: count)
    alpha.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.translateBy(x: 92, y: 92)
        context.scaleBy(x: 104 / 24, y: 104 / 24)
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(moonPath())
        context.strokePath()
    }
    let sigma = 9.0 * Double(scale)
    let radius = Int(ceil(sigma * 3))
    var kernel = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
    let sum = kernel.reduce(0, +)
    kernel = kernel.map { $0 / sum }
    var input = alpha.map { Float($0) / 255 }
    var temporary = [Float](repeating: 0, count: count)
    var blurred = temporary
    input.withUnsafeMutableBytes { source in
        temporary.withUnsafeMutableBytes { middle in
            blurred.withUnsafeMutableBytes { destination in
                var a = vImage_Buffer(
                    data: source.baseAddress!, height: vImagePixelCount(size), width: vImagePixelCount(size),
                    rowBytes: size * MemoryLayout<Float>.size)
                var b = vImage_Buffer(data: middle.baseAddress!, height: a.height, width: a.width, rowBytes: a.rowBytes)
                var c = vImage_Buffer(
                    data: destination.baseAddress!, height: a.height, width: a.width, rowBytes: a.rowBytes)
                kernel.withUnsafeBufferPointer { k in
                    precondition(
                        vImageConvolve_PlanarF(
                            &a, &b, nil, 0, 0, k.baseAddress!, 1, UInt32(k.count), 0, vImage_Flags(kvImageEdgeExtend))
                            == kvImageNoError)
                    precondition(
                        vImageConvolve_PlanarF(
                            &b, &c, nil, 0, 0, k.baseAddress!, UInt32(k.count), 1, 0, vImage_Flags(kvImageEdgeExtend))
                            == kvImageNoError)
                }
            }
        }
    }
    var pixels = [UInt8](repeating: 0, count: count * 4)
    for i in 0..<count {
        let stroke = Double(alpha[i]) / 255
        let opacity = stroke + (1 - stroke) * Double(blurred[i]) * 0.45
        for channel in 0..<3 { pixels[i * 4 + channel] = UInt8((color.values[channel] * opacity * 255).rounded()) }
        pixels[i * 4 + 3] = UInt8((opacity * 255).rounded())
    }
    let data = Data(pixels) as CFData
    return CGImage(
        width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.displayP3)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

public func png(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}

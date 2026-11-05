import CoreGraphics
import QuartzCore
import Testing

@testable import DesignSystem

@Test func pressValuesRespectReduceMotion() {
    #expect(
        PressStyle.values(isPressed: true, reduceMotion: false) == .init(scale: 0.97, opacity: 0.85, duration: 0.12))
    #expect(PressStyle.values(isPressed: true, reduceMotion: true) == .init(scale: 1, opacity: 0.85, duration: 0))
    #expect(PressStyle.values(isPressed: false, reduceMotion: false) == .init(scale: 1, opacity: 1, duration: 0.12))
    #expect(PressStyle.values(isPressed: false, reduceMotion: true) == .init(scale: 1, opacity: 1, duration: 0))
    #expect(PressTokens.curve == [0.25, 0.1, 0.25, 1])
}

@Test @MainActor func skyLayerUsesP3StopsIncludingExactMidpoint() throws {
    for appearance in TokenAppearance.allCases {
        let layer = CfSkyLayer()
        layer.appearance = appearance
        layer.frame = CGRect(x: 0, y: 0, width: 537, height: 711)
        #expect(layer.bounds.size == CGSize(width: 537, height: 711))
        #expect(layer.startPoint == CGPoint(x: 0.5, y: 0))
        #expect(layer.endPoint == CGPoint(x: 0.5, y: 1))
        let stops = appearance == .light ? SkyRamp.light : SkyRamp.dark
        #expect(layer.locations?.map(\.doubleValue) == stops.map(\.location))
        let colors = try #require(layer.colors as? [CGColor])
        #expect(colors.count == stops.count)
        #expect(colors.allSatisfy { $0.colorSpace?.name == CGColorSpace.displayP3 })
        #expect(layer.locations?.contains(NSNumber(value: appearance == .light ? 0.55 : 0.6)) == true)
        #expect(layer.mask == nil)
        #expect(layer.filters == nil)
        #expect(layer.shadowOpacity == 0)
    }
}

@Test @MainActor func patternTileMatchesTheCSSRadialFade() {
    for appearance in TokenAppearance.allCases {
        for scale in [2.0, 3.0] {
            let image = PatternDots.tile(color: ColorToken.skyTitle.components(for: appearance), scale: scale)
            let side = Int(7 * scale)
            #expect(image.width == side && image.height == side)
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            pixels.withUnsafeMutableBytes { data in
                let context = CGContext(
                    data: data.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.displayP3)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            for y in 0..<side {
                for x in 0..<side {
                    let radius = hypot((Double(x) + 0.5) / scale - 3.5, (Double(y) + 0.5) / scale - 3.5)
                    let expected = 0.16 * min(1, max(0, (1.5 - radius) / 0.5))
                    #expect(abs(Double(pixels[(y * side + x) * 4 + 3]) / 255 - expected) <= 1 / 255.0)
                }
            }
        }
    }
}

@Test @MainActor func moonShapeScalesAndKeepsTheSVGOrientation() {
    let rect = CGRect(x: 17, y: 29, width: 56, height: 56)
    let path = MoonShape().path(in: rect)
    #expect(path.contains(CGPoint(x: 17 + 6 * 56 / 24.0, y: 29 + 12 * 56 / 24.0)))
    #expect(!path.contains(CGPoint(x: 17 + 17 * 56 / 24.0, y: 29 + 6 * 56 / 24.0)))
    #expect(abs(path.boundingRect.minX - (17 + 3 * 56 / 24.0)) < 0.01)
    #expect(abs(path.boundingRect.minY - (29 + 3 * 56 / 24.0)) < 0.01)
    #expect(abs(path.boundingRect.maxX - (17 + 21 * 56 / 24.0)) < 0.01)
    #expect(abs(path.boundingRect.maxY - (29 + 21 * 56 / 24.0)) < 0.01)
}

import CoreGraphics
import DesignSystem
import Foundation
import QuartzCore
import Testing

@testable import Launch

struct LaunchRadialLayerTests {
    private func pixels(_ layer: CALayer, scale: CGFloat) throws -> (bytes: [UInt8], width: Int) {
        let width = Int((layer.bounds.width * scale).rounded())
        var bytes = [UInt8](repeating: 0, count: width * width * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: width, height: width, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
        }
        return (bytes, width)
    }

    @Test func nativeHaloRendersOutsideTheClippedDiscOnBothAxesAtBothScales() throws {
        for appearance in [TokenAppearance.light, .dark] {
            for scale: CGFloat in [2, 3] {
                let layer = LaunchRadialLayer(
                    size: 500, centre: CGPoint(x: 250, y: 250), radius: 250,
                    color: ColorToken.dawn.components(for: appearance).cgColor,
                    stops: LaunchGlow.haloStops, scale: scale)
                #expect(layer.type == .radial)
                #expect(layer.endPoint == CGPoint(x: 1, y: 1))
                let (bytes, width) = try pixels(layer, scale: scale)
                func alpha(_ radius: CGFloat, vertical: Bool = false) -> UInt8 {
                    let x = Int((250 + (vertical ? 0 : radius)) * scale)
                    let y = Int((250 + (vertical ? radius : 0)) * scale)
                    return bytes[(y * width + x) * 4 + 3]
                }
                for vertical in [false, true] {
                    #expect(alpha(0, vertical: vertical) == 0)
                    #expect(alpha(85, vertical: vertical) == 0)
                    #expect(alpha(100, vertical: vertical) > 40)
                    #expect(alpha(200, vertical: vertical) < alpha(100, vertical: vertical))
                }
                #expect(abs(Int(alpha(100)) - Int(alpha(100, vertical: true))) <= 1)
            }
        }
    }

    @Test func nativeSunUsesTheDesignedRadiusInsteadOfItsInscribedRadius() throws {
        for scale: CGFloat in [2, 3] {
            let layer = LaunchRadialLayer(
                size: 180, centre: CGPoint(x: 90, y: 90), radius: 127.3, color: LaunchPaint.white.cgColor,
                stops: [(0, 1), (70 / 127.3, 1), (91.6 / 127.3, 0), (1, 0)], scale: scale)
            let (bytes, width) = try pixels(layer, scale: scale)
            let alpha = { (radius: Int) in bytes[(Int(90 * scale) * width + Int(CGFloat(90 + radius) * scale)) * 4 + 3]
            }
            #expect(alpha(60) == 255)
            #expect(alpha(80) > 100 && alpha(80) < 160)
            #expect(alpha(89) < 40)
        }
    }
}

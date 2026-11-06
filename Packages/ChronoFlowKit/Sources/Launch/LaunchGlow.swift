import CoreGraphics
import DesignSystem
import Foundation

nonisolated enum LaunchGlow {
    static var haloStops: [(Double, Double)] { LaunchPaint.haloStops }

    static func plane(color: CGColor, scale: CGFloat) -> CGImage {
        let pixels = Int(48 * scale)
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        let stops = LaunchPaint.planeAlphas.map { color.copy(alpha: $0)! }
        let gradient = CGGradient(
            colorsSpace: color.colorSpace, colors: stops as CFArray,
            locations: (0..<stops.count).map { Double($0) / Double(stops.count - 1) })!
        context.drawRadialGradient(
            gradient, startCenter: CGPoint(x: 24, y: 24), startRadius: 0,
            endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: 20, y: 20, width: 8, height: 8))
        return context.makeImage()!
    }
}

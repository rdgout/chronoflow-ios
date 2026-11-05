import CoreGraphics
import Foundation
import SwiftUI

public struct PatternDots: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    private let token: ColorToken

    public init(color: ColorToken = .skyTitle) { token = color }

    public var body: some View {
        NativePattern(color: token.components(for: colorScheme == .dark ? .dark : .light), scale: displayScale)
            .accessibilityHidden(true)
    }

    public static func tile(color: TokenRGBA, scale: CGFloat) -> CGImage {
        precondition(scale > 0)
        let points = PatternTokens.tile
        let pixels = Int((points * scale).rounded(.up))
        var data = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for y in 0..<pixels {
            for x in 0..<pixels {
                let radius = hypot((Double(x) + 0.5) / scale - points / 2, (Double(y) + 0.5) / scale - points / 2)
                let fade = min(
                    1, max(0, (PatternTokens.fadeRadius - radius) / (PatternTokens.fadeRadius - PatternTokens.radius)))
                let alpha = color.alpha * PatternTokens.alpha * fade
                let index = (y * pixels + x) * 4
                for (channel, value) in [color.red, color.green, color.blue, 1].enumerated() {
                    data[index + channel] = UInt8((value * alpha * 255).rounded())
                }
            }
        }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
    }
}

#if canImport(UIKit)
    import UIKit

    private struct NativePattern: UIViewRepresentable {
        let color: TokenRGBA
        let scale: CGFloat
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ view: UIView, context: Context) {
            let image = UIImage(cgImage: PatternDots.tile(color: color, scale: scale), scale: scale, orientation: .up)
            view.layer.contentsScale = scale
            view.layer.backgroundColor = UIColor(patternImage: image).cgColor
        }
    }
#else
    import AppKit

    private struct NativePattern: NSViewRepresentable {
        let color: TokenRGBA
        let scale: CGFloat
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.wantsLayer = true
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {
            let image = NSImage(
                cgImage: PatternDots.tile(color: color, scale: scale),
                size: CGSize(width: PatternTokens.tile, height: PatternTokens.tile))
            view.layer?.contentsScale = scale
            view.layer?.backgroundColor = NSColor(patternImage: image).cgColor
        }
    }
#endif

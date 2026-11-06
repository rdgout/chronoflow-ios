import CoreText
import Foundation
import Testing

@testable import DesignSystem

#if canImport(UIKit)
    import UIKit
#endif

@Suite struct ExactLineTextLayoutTests {
    @Test func headlineWrapsAtTheBoardWidthWithExactHalfLeading() async throws {
        try await FontRegistry.register()
        let style = Typography.headline
        let font = style.coreTextFont
        let text = NSAttributedString(
            string: "Plan your clock shift for your next trip",
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): style.tracking,
            ])
        let width = CGFloat(390) - 2 * WelcomeTokens.gutter
        let pitch = CGFloat(try #require(style.lineHeight))
        let layout = ExactLineTextLayout(text: text, width: width, lineHeight: pitch)
        #expect(layout.ranges.count == 3)
        #expect(layout.height == CGFloat(3) * pitch)
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        #expect(natural > pitch)
        for index in layout.ranges.indices {
            let frame = layout.frame(for: index, width: width, naturalHeight: natural)
            #expect(abs(frame.midY - (CGFloat(index) + 0.5) * pitch) < 1e-9)
            #expect(frame.height == natural)
            if index > 0 {
                let previous = layout.frame(for: index - 1, width: width, naturalHeight: natural)
                #expect(abs(frame.minY - previous.minY - pitch) < 1e-9)
            }
        }
    }

    @Test func exactLineWrappingPreservesUnicodeAndReflowsWithoutLosingText() async throws {
        try await FontRegistry.register()
        for string in [
            "Plan de verschuiving van je biologische klok voor je volgende reis", "Agj\nAgj", "Agj\n", "", "🌙égj",
        ] {
            let text = NSAttributedString(
                string: string,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): Typography.headline.coreTextFont])
            var previousCount = Int.max
            for width: CGFloat in [0, 150, 327, 342, 418, 1000] {
                let layout = ExactLineTextLayout(text: text, width: width, lineHeight: 48)
                #expect(layout.ranges.reduce(0) { $0 + $1.length } == text.length)
                #expect(layout.ranges.count <= previousCount)
                previousCount = layout.ranges.count
                #expect(layout.ranges.map { text.attributedSubstring(from: $0).string }.joined() == string)
                if string == "Agj\n" { #expect(layout.line(at: layout.ranges.count - 1).string.isEmpty) }
                for index in layout.ranges.indices {
                    let line = layout.line(at: index).string
                    #expect(line == line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    #if canImport(UIKit)

        @Test @MainActor func scaledHeadlinePitchAndGlyphsFitNaturalLabels() async throws {
            try await FontRegistry.register()
            for category in [UIContentSizeCategory.small, .large, .extraExtraLarge, .accessibilityExtraExtraExtraLarge]
            {
                let style = Typography.headline
                let font = style.uiFont(compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
                let pitch = try #require(style.lineHeight) * font.pointSize / style.size
                let view = ExactLineTextView()
                view.font = font
                view.lineHeight = pitch
                view.text = NSAttributedString(
                    string: "Ágj\nAgj\nPlan de verschuiving van je biologische klok voor je volgende reis",
                    attributes: [.font: font, .kern: style.tracking * font.pointSize / style.size])
                for width: CGFloat in [327, 342, 418] {
                    let layout = view.layout(width: width)
                    view.frame = CGRect(x: 0, y: 0, width: width, height: layout.height)
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                    #expect(!view.clipsToBounds)
                    #expect(view.subviews.count == layout.ranges.count)
                    for (index, label) in view.subviews.compactMap({ $0 as? UILabel }).enumerated() {
                        #expect(abs(label.center.y - (CGFloat(index) + 0.5) * pitch) < 1e-9)
                        #expect(label.bounds.height == font.lineHeight)
                        #expect(!label.isAccessibilityElement)
                    }
                    let reference = UIView(frame: view.bounds)
                    for index in layout.ranges.indices {
                        let label = UILabel()
                        label.attributedText = layout.line(at: index)
                        label.frame = CGRect(
                            x: 0, y: CGFloat(index) * pitch + (pitch - font.lineHeight) / 2,
                            width: width, height: font.lineHeight)
                        reference.addSubview(label)
                    }
                    for scale: CGFloat in [2, 3] {
                        let exact = try renderInk(view, font: font, scale: scale)
                        let natural = try renderInk(reference, font: font, scale: scale)
                        #expect(exact.bounds == natural.bounds, "Clipped ascender/descender: \(category)")
                        #expect(exact.bytes == natural.bytes, "Changed glyphs: \(category)")
                    }
                }
            }
        }

        @Test @MainActor func glyphCanvasDetectsClippingOutsideTheLineBox() async throws {
            try await FontRegistry.register()
            let font = Typography.headline.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
            let view = ExactLineTextView()
            view.font = font
            view.lineHeight = font.lineHeight / 2
            view.text = NSAttributedString(string: "Ágj", attributes: [.font: font])
            view.frame.size = CGSize(width: 4 * font.pointSize, height: view.lineHeight)
            for scale: CGFloat in [2, 3] {
                view.clipsToBounds = false
                let full = try renderInk(view, font: font, scale: scale)
                view.clipsToBounds = true
                let clipped = try renderInk(view, font: font, scale: scale)
                #expect(full.bytes != clipped.bytes)
                #expect(full.bounds.height > clipped.bounds.height)
            }
        }

        @MainActor
        private func renderInk(_ view: UIView, font: UIFont, scale: CGFloat) throws -> (bounds: CGRect, bytes: [UInt8])
        {
            // Resizing a UILabel changes baseline rounding; keep its natural bounds and pad the canvas instead.
            let margin = ceil(font.ascender - font.descender + font.leading)
            let canvas = UIView(
                frame: CGRect(
                    x: 0, y: 0, width: view.bounds.width + 2 * margin, height: view.bounds.height + 2 * margin))
            canvas.addSubview(view)
            view.frame.origin = CGPoint(x: margin, y: margin)
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            view.layoutIfNeeded()
            display(canvas.layer)
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image {
                canvas.layer.render(in: $0.cgContext)
            }
            let cgImage = try #require(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(
                    CGContext(
                        data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                        bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            }
            var minX = cgImage.width
            var minY = cgImage.height
            var maxX = -1
            var maxY = -1
            for y in 0..<cgImage.height {
                for x in 0..<cgImage.width where bytes[(y * cgImage.width + x) * 4 + 3] > 0 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            let ink = maxX < 0 ? CGRect.null : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            #expect(!ink.isNull)
            #expect(ink.minX > 0 && ink.minY > 0)
            #expect(ink.maxX < CGFloat(cgImage.width) && ink.maxY < CGFloat(cgImage.height))
            view.removeFromSuperview()
            return (ink, bytes)
        }
    #endif
}

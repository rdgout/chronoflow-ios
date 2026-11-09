import DesignSystem
import QuartzCore
import SnapshotSupport
import Testing

@testable import Auth

struct AuthCardShadowTests {
    @Test func cardShadowBitmapFallsBelowTheCardAtBothDisplayScales() throws {
        let shadow = AuthCardShadowLayer()
        for scale: CGFloat in [2, 3] {
            for height: CGFloat in [428, 520] {
                for appearance in [TokenAppearance.light, .dark, .light] {
                    shadow.bounds = CGRect(x: 0, y: 0, width: 343, height: height)
                    shadow.contentsScale = scale
                    shadow.appearance = appearance
                    shadow.setNeedsLayout()
                    shadow.layoutIfNeeded()
                    let ink = try #require(shadow.sublayers?.first)
                    let image = try #require(ink.contents) as! CGImage
                    let raster = try SnapshotRaster(image: image)
                    #expect(raster.width == Int(ceil(ink.bounds.width * scale)))
                    #expect(raster.height == Int(ceil(ink.bounds.height * scale)))
                    #expect(ink.contentsScale == scale)
                    let x = raster.width / 2
                    let top = Int((-ink.frame.minY - 6) * scale)
                    let bottom = Int((height - ink.frame.minY + 6) * scale)
                    let above = raster.bytes[(top * raster.width + x) * 4 + 3]
                    let below = raster.bytes[(bottom * raster.width + x) * 4 + 3]
                    #expect(below > above, "Image rows must carry more shadow below the card than above it")
                }
            }
        }
    }

    @Test func cardShadowMatchesBoardInkBelowAndBesideTheCard() throws {
        let size = AuthShadowBoard.size
        let sky = CfSkyLayer()
        sky.frame = CGRect(origin: .zero, size: size)
        let shadow = AuthCardShadowLayer()
        shadow.frame = CGRect(x: 16, y: 300, width: 343, height: 428)
        for scale: CGFloat in [2, 3] {
            shadow.contentsScale = scale
            shadow.setNeedsLayout()
            for appearance in [TokenAppearance.light, .dark, .light] {
                sky.appearance = appearance
                shadow.appearance = appearance
                sky.layoutIfNeeded()
                shadow.layoutIfNeeded()
                let raster = try render(sky, shadow: shadow, size: size, scale: scale)
                shadow.isHidden = true
                let unshadowed = try render(sky, shadow: shadow, size: size, scale: scale)
                shadow.isHidden = false
                for sample in AuthShadowBoard.samples {
                    let expected = appearance == .dark ? sample.dark : sample.light
                    let actual = sample.mean(in: raster)
                    print("Auth card shadow \(appearance) \(scale)×, \(sample.name): RGB \(actual); board \(expected)")
                    for (actual, expected) in zip(actual, expected) {
                        #expect(abs(actual - expected) <= 4, "sRGB board ink tolerance is four 8-bit levels")
                    }
                    let minimumInk = appearance == .dark ? sample.minimumDarkInk : sample.minimumLightInk
                    #expect(sample.mean(in: unshadowed)[0] - actual[0] >= minimumInk, "Require ink in each region")
                }
            }
        }
    }

    private func render(_ sky: CALayer, shadow: AuthCardShadowLayer, size: CGSize, scale: CGFloat) throws
        -> SnapshotRaster
    {
        let context = try #require(
            CGContext(
                data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                bytesPerRow: Int(size.width * scale) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        sky.render(in: context)
        context.restoreGState()
        if !shadow.isHidden {
            let ink = try #require(shadow.sublayers?.first)
            let image = try #require(ink.contents) as! CGImage
            let frame = ink.frame.offsetBy(dx: shadow.frame.minX, dy: shadow.frame.minY)
            // macOS CALayer.render flips CGImage contents; composite image rows as UIKit displays them.
            context.draw(
                image,
                in: CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height))
        }
        let card = shadow.frame
        context.setFillColor(ColorToken.card.components(for: shadow.appearance).cgColor)
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: card.minX, y: size.height - card.maxY, width: card.width, height: card.height),
                cornerWidth: AuthTokens.cardRadius, cornerHeight: AuthTokens.cardRadius, transform: nil))
        context.fillPath()
        return try SnapshotRaster(image: #require(context.makeImage()))
    }
}

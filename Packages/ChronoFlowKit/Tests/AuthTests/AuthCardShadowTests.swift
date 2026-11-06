import DesignSystem
import QuartzCore
import SnapshotSupport
import Testing

@testable import Auth

struct AuthCardShadowTests {
    @Test func cardShadowMatchesBoardInkBelowAndBesideTheCard() throws {
        let size = AuthShadowBoard.size
        let card = CGRect(x: 16, y: 300, width: 343, height: 428)
        let sky = CfSkyLayer()
        sky.frame = CGRect(origin: .zero, size: size)
        let shadow = AuthCardShadowLayer()
        shadow.frame = card
        shadow.contentsScale = 3
        sky.addSublayer(shadow)
        let surface = CALayer()
        surface.frame = card
        surface.cornerRadius = AuthTokens.cardRadius
        sky.addSublayer(surface)
        for appearance in [TokenAppearance.light, .dark, .light] {
            sky.appearance = appearance
            shadow.appearance = appearance
            surface.backgroundColor = ColorToken.card.components(for: appearance).cgColor
            sky.layoutIfNeeded()
            shadow.layoutIfNeeded()
            let raster = try render(sky, size: size)
            shadow.isHidden = true
            let unshadowed = try render(sky, size: size)
            shadow.isHidden = false
            for sample in AuthShadowBoard.samples {
                let expected = appearance == .dark ? sample.dark : sample.light
                let actual = sample.mean(in: raster)
                print("Auth card shadow \(appearance), \(sample.name): RGB \(actual); board \(expected)")
                for (actual, expected) in zip(actual, expected) {
                    #expect(abs(actual - expected) <= 4, "sRGB board ink tolerance is four 8-bit levels")
                }
                let minimumInk = appearance == .dark ? sample.minimumDarkInk : sample.minimumLightInk
                #expect(sample.mean(in: unshadowed)[0] - actual[0] >= minimumInk, "Require ink in each region")
            }
        }
    }

    private func render(_ layer: CALayer, size: CGSize) throws -> SnapshotRaster {
        let context = try #require(
            CGContext(
                data: nil, width: Int(size.width * 3), height: Int(size.height * 3), bitsPerComponent: 8,
                bytesPerRow: Int(size.width * 3) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: size.height * 3)
        context.scaleBy(x: 3, y: -3)
        layer.render(in: context)
        return try SnapshotRaster(image: #require(context.makeImage()))
    }

}

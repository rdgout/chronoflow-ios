import DesignSystem
import QuartzCore

nonisolated final class AuthCardShadowLayer: CALayer {
    var appearance: TokenAppearance = .light {
        didSet { if oldValue != appearance { setNeedsLayout() } }
    }

    override init() {
        super.init()
        setNeedsLayout()
    }

    override init(layer: Any) {
        appearance = (layer as? AuthCardShadowLayer)?.appearance ?? .light
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSublayers() {
        super.layoutSublayers()
        guard !bounds.isEmpty else { return }
        let spread = appearance == .dark ? AuthTokens.darkShadowSpread : AuthTokens.lightShadowSpread
        let radius = max(0, AuthTokens.cardRadius + spread)
        let blur = appearance == .dark ? AuthTokens.darkShadowRadius : AuthTokens.lightShadowRadius
        let y = appearance == .dark ? AuthTokens.darkShadowY : AuthTokens.lightShadowY
        let padding = ceil(blur * 3 + abs(y))
        let extent = bounds.insetBy(dx: -padding, dy: -padding)
        let scale = contentsScale
        guard
            let context = CGContext(
                data: nil, width: Int(ceil(extent.width * scale)), height: Int(ceil(extent.height * scale)),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.scaleBy(x: scale, y: scale)
        // Bake the blur so CPU snapshot capture does not depend on render-server effects.
        // Quartz bitmap Y points up; UIKit displays the image's first row at the top.
        context.setShadow(
            offset: CGSize(width: 0, height: -y * scale), blur: blur * 2 * scale,
            color: ColorToken.authShadow.components(for: appearance).cgColor)
        context.setFillColor(ColorToken.card.components(for: appearance).cgColor)
        context.addPath(
            CGPath(
                roundedRect: CGRect(origin: CGPoint(x: padding, y: padding), size: bounds.size)
                    .insetBy(dx: -spread, dy: -spread), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ink = sublayers?.first ?? CALayer()
        if ink.superlayer == nil { addSublayer(ink) }
        ink.frame = extent
        ink.contentsScale = scale
        ink.contents = context.makeImage()
        CATransaction.commit()
    }
}

#if canImport(UIKit)
    import CoreText
    import DesignSystem
    import UIKit

    nonisolated public final class StatusLineLayer: CALayer {
        public let replicator = CAReplicatorLayer()
        public let dot = CALayer()
        public private(set) var text: CATextLayer?
        private let sampledDots = (0..<3).map { _ in CALayer() }
        private var ink: CGColor?

        public override init() {
            super.init()
            replicator.instanceCount = 3
            replicator.instanceDelay = 0.2
            replicator.instanceTransform = CATransform3DMakeTranslation(7, 0, 0)
            replicator.addSublayer(dot)
            addSublayer(replicator)
            for dot in sampledDots { addSublayer(dot) }
        }

        public override init(layer: Any) { super.init(layer: layer) }
        public required init?(coder: NSCoder) { super.init(coder: coder) }

        func configure(color: CGColor, scale: CGFloat) {
            ink = color
            contentsScale = scale
            for layer in [dot] + sampledDots {
                layer.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
                layer.cornerRadius = 2
                layer.backgroundColor = color
                layer.contentsScale = scale
            }
        }

        @MainActor
        public func prepareText(_ string: String) {
            guard text == nil else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let font = Typography.status.coreTextFont
            let attributed = NSAttributedString(
                string: string,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink!,
                ])
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = ceil(CTLineGetTypographicBounds(line, &ascent, &descent, nil) * contentsScale) / contentsScale
            let left = (bounds.width - width - 6 - 18) / 2
            let label = CATextLayer()
            label.contentsScale = contentsScale
            label.string = attributed
            label.frame = CGRect(x: left, y: (20 - ascent - descent) / 2, width: width, height: 20)
            addSublayer(label)
            text = label
            replicator.frame = CGRect(x: left + width + 6, y: 0, width: 18, height: 20)
            dot.position = CGPoint(x: 2, y: 10)
            for (index, layer) in sampledDots.enumerated() {
                layer.position = CGPoint(x: replicator.frame.minX + 2 + CGFloat(index) * 7, y: 10)
            }
            CATransaction.commit()
        }

        func applyReplicaOpacities(_ opacities: [Double]) {
            replicator.isHidden = true
            for (index, layer) in sampledDots.enumerated() {
                layer.isHidden = opacities.count != 3
                if opacities.count == 3 { layer.opacity = Float(opacities[index]) }
            }
        }

        func useLiveReplicas() {
            replicator.isHidden = false
            for dot in sampledDots { dot.isHidden = true }
        }
    }
#endif

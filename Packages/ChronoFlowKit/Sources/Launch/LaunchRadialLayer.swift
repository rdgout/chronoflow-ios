import Foundation
import QuartzCore

nonisolated final class LaunchRadialLayer: CAGradientLayer {
    init(size: CGFloat, centre: CGPoint, radius: CGFloat, color: CGColor, stops: [(Double, Double)], scale: CGFloat) {
        super.init()
        type = .radial
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        position = centre
        contentsScale = scale
        startPoint = CGPoint(x: 0.5, y: 0.5)
        // CA interprets the two end-point deltas as ellipse radii, not a radius vector.
        endPoint = CGPoint(x: 0.5 + radius / size, y: 0.5 + radius / size)
        colors = stops.map { color.copy(alpha: $0.1)! }
        locations = stops.map { NSNumber(value: $0.0) }
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

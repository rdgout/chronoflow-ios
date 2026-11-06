#if canImport(UIKit)
    import DesignSystem
    import UIKit

    public final class LaunchScene {
        public let container = CALayer()
        public internal(set) var layers: [LayerID: CALayer] = [:]
        public let statusLine = StatusLineLayer()
        public let size: CGSize
        public let traits: UITraitCollection
        public internal(set) var timeline: LaunchTimeline
        public internal(set) var t0: CFTimeInterval?

        public init(size: CGSize, traits: UITraitCollection, reduceMotion: Bool) {
            self.size = size
            self.traits = traits
            timeline = .opening(size: size, reduceMotion: reduceMotion)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            buildLayers()
            apply(timeline.sample(at: .zero))
            CATransaction.commit()
        }

        public func prepareStatus() {
            statusLine.prepareText(
                String(localized: "Getting your plan ready", bundle: .module), compatibleWith: traits)
        }

        public func layer(_ id: LayerID) -> CALayer { layers[id]! }

        public func apply(_ values: [LayerID: LayerValues]) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (id, properties) in values {
                let target = layer(id)
                target.removeAllAnimations()
                for (key, value) in properties.properties {
                    target.setValue(animationValue(value, layer: id, keyPath: key), forKeyPath: key)
                    if key == "transform.scale" {
                        // render(in:) ignores 3D transforms, including an otherwise planar scale with scaled Z.
                        var transform = target.transform
                        transform.m33 = 1
                        target.transform = transform
                    }
                }
            }
            statusLine.applyReplicaOpacities(values[.statusDot]?.replicaOpacities ?? [])
            CATransaction.commit()
        }

        func animationValue(_ value: TrackValue, layer: LayerID, keyPath: String) -> Any {
            switch value {
            case .scalar(let number): return NSNumber(value: number)
            case .point(var point):
                if layer == .moon && keyPath == "position" {
                    let scale = traits.displayScale
                    point.x += (size.width / 2 * scale).rounded() / scale - size.width / 2
                    point.y += (size.height / 2 * scale).rounded() / scale - size.height / 2
                }
                return NSValue(cgPoint: point)
            }
        }
    }
#endif

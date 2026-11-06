#if canImport(UIKit)
    import UIKit

    extension LaunchScene {
        public func play(_ timeline: LaunchTimeline, at firstCommit: CFTimeInterval) {
            precondition(timeline.size == size && timeline.reduceMotion == self.timeline.reduceMotion)
            precondition(firstCommit > 0 && (t0 == nil || t0 == firstCommit))
            self.timeline = timeline
            t0 = firstCommit
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let keys = Set(timeline.tracks.map { $0.layer.rawValue + "." + $0.keyPath })
            for (id, layer) in layers {
                for key in layer.animationKeys() ?? [] where !keys.contains(id.rawValue + "." + key) {
                    layer.removeAnimation(forKey: key)
                }
            }
            statusLine.useLiveReplicas()
            for track in timeline.tracks {
                let target = layer(track.layer)
                target.setValue(
                    animationValue(track.values.last!, layer: track.layer, keyPath: track.keyPath),
                    forKeyPath: track.keyPath)
                guard track.values.count > 1 else {
                    target.removeAnimation(forKey: track.keyPath)
                    continue
                }
                let animation = CAKeyframeAnimation(keyPath: track.keyPath)
                animation.duration = track.keyTimes.last!
                animation.keyTimes = track.keyTimes.map { NSNumber(value: $0 / animation.duration) }
                animation.values = track.values.map { animationValue($0, layer: track.layer, keyPath: track.keyPath) }
                animation.timingFunctions = track.curves.map {
                    CAMediaTimingFunction(controlPoints: Float($0.x1), Float($0.y1), Float($0.x2), Float($0.y2))
                }
                animation.calculationMode = .linear
                animation.beginTime = firstCommit
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                animation.repeatCount = track.repeatInterval == nil ? 0 : .infinity
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
                target.add(animation, forKey: track.keyPath)
            }
            CATransaction.commit()
        }
    }
#endif

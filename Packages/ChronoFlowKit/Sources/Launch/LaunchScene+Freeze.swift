#if canImport(UIKit)
    import AppCore
    import UIKit

    extension LaunchScene {
        public func freeze(at time: Duration) {
            precondition(time >= .zero)
            guard let t0 else { preconditionFailure("Commit playback before freezing") }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.speed = 0
            // Tracks retain their absolute media epoch when the parent clock is paused.
            container.timeOffset = t0 + time.timeInterval
            CATransaction.commit()
            CATransaction.flush()
        }
    }
#endif

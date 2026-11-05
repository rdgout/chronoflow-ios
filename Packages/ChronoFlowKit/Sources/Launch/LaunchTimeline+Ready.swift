import AppCore
import Foundation

extension LaunchTimeline {
    nonisolated public func withReadyExit(at start: Duration) -> Self {
        var timeline = withoutExit()
        let exit = max(reduceMotion ? 0 : 1.5, start.timeInterval)
        timeline.append(
            .container, "opacity", start: exit, end: exit + (reduceMotion ? 0.3 : 0.4), value: .scalar(0),
            curve: .easeOut)
        if !reduceMotion {
            timeline.append(
                .container, "transform.scale", start: exit, end: exit + 0.4, value: .scalar(1.08), curve: .easeOut)
        }
        return timeline
    }

    nonisolated public func withStatus(at start: Duration) -> Self {
        var timeline = self
        let time = max(0, start.timeInterval)
        timeline.set(
            .status, "opacity", times: time == 0 ? [0, 0.3] : [0, time, time + 0.3],
            scalars: time == 0 ? [0, 1] : [0, 0, 1], curves: time == 0 ? [.easeOut] : [.linear, .easeOut])
        timeline.replace(
            Track(
                layer: .statusDot, keyPath: "opacity", keyTimes: reduceMotion ? [0] : [0, 0.48, 0.96, 1.2],
                values: (reduceMotion ? [1.0] : [0.25, 1, 0.25, 0.25]).map(TrackValue.scalar),
                curves: reduceMotion ? [] : [.easeInOut, .easeInOut, .linear], repeatInterval: reduceMotion ? nil : 1.2,
                replicaCount: 3, replicaDelay: reduceMotion ? 0 : 0.2))
        return timeline
    }
}

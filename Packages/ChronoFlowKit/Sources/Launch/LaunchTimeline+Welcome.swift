import CoreGraphics
import Foundation

extension LaunchTimeline {
    nonisolated public func withWelcomeExit(at start: Duration, size: CGSize, moonTarget: CGRect) -> Self {
        precondition(size == self.size)
        precondition(
            moonTarget.width > 0 && moonTarget.width.isFinite && moonTarget.midX.isFinite && moonTarget.midY.isFinite)
        if reduceMotion { return withReadyExit(at: start) }
        var timeline = withoutExit()
        let exit = max(1.6, start.timeInterval)
        timeline.append(.band, "opacity", start: exit, end: exit + 0.7, value: .scalar(0), curve: .easeOut)
        timeline.append(.stars, "opacity", start: exit + 0.1, end: exit + 0.7, value: .scalar(0.2), curve: .easeOut)
        for layer in [LayerID.sun, .halo] {
            timeline.append(layer, "opacity", start: exit, end: exit + 0.6, value: .scalar(0), curve: .easeOut)
            timeline.append(
                layer, "transform.translation.y", start: exit, end: exit + 0.6, value: .scalar(120), curve: .easeOut)
        }
        timeline.append(.path, "opacity", start: exit, end: exit + 0.4, value: .scalar(0), curve: .linear)
        timeline.append(.wordmark, "opacity", start: exit, end: exit + 0.3, value: .scalar(0), curve: .easeOut)
        timeline.append(
            .wordmark, "transform.translation.y", start: exit, end: exit + 0.3, value: .scalar(-6), curve: .easeOut)
        timeline.append(
            .moon, "position", start: exit, end: exit + 0.7,
            value: .point(CGPoint(x: moonTarget.midX, y: moonTarget.midY)), curve: .easeInOut)
        timeline.append(
            .moon, "transform.scale", start: exit, end: exit + 0.7, value: .scalar(moonTarget.width / 104),
            curve: .easeInOut)
        timeline.append(.container, "opacity", start: exit + 0.7, end: exit + 0.95, value: .scalar(0), curve: .easeOut)
        return timeline
    }
}

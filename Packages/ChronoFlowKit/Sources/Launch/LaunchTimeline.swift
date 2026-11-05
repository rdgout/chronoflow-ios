import AppCore
import CoreGraphics
import Foundation

nonisolated public struct LaunchTimeline: Sendable, Equatable {
    public struct Track: Sendable, Equatable {
        public let layer: LayerID
        public let keyPath: String
        // Seconds from the first overlay commit; the CA adapter normalizes these per track.
        public let keyTimes: [Double]
        public let values: [TrackValue]
        public let curves: [CubicBezier]
        public let repeatInterval: Double?
        public let replicaCount: Int
        public let replicaDelay: Double

        init(
            layer: LayerID, keyPath: String, keyTimes: [Double], values: [TrackValue], curves: [CubicBezier],
            repeatInterval: Double? = nil, replicaCount: Int = 1, replicaDelay: Double = 0
        ) {
            precondition(!keyTimes.isEmpty && keyTimes.count == values.count && curves.count == values.count - 1)
            precondition(zip(keyTimes, keyTimes.dropFirst()).allSatisfy { $0 < $1 })
            self.layer = layer
            self.keyPath = keyPath
            self.keyTimes = keyTimes
            self.values = values
            self.curves = curves
            self.repeatInterval = repeatInterval
            self.replicaCount = replicaCount
            self.replicaDelay = replicaDelay
        }

        public func sample(at time: Duration) -> TrackValue {
            value(at: time.timeInterval)
        }

        func value(at seconds: Double) -> TrackValue {
            var time = seconds
            if let repeatInterval, time > keyTimes[0] {
                time = keyTimes[0] + (time - keyTimes[0]).truncatingRemainder(dividingBy: repeatInterval)
            }
            if time <= keyTimes[0] { return values[0] }
            guard let upper = keyTimes.firstIndex(where: { $0 > time }) else { return values.last! }
            let lower = upper - 1
            let progress = (time - keyTimes[lower]) / (keyTimes[upper] - keyTimes[lower])
            return values[lower].interpolated(to: values[upper], progress: curves[lower].value(at: progress))
        }
    }

    public private(set) var tracks: [Track]
    public let size: CGSize
    public let reduceMotion: Bool

    public static func opening(size: CGSize, reduceMotion: Bool) -> Self {
        precondition(size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite)
        var timeline = Self(tracks: [], size: size, reduceMotion: reduceMotion)
        for layer in LayerID.allCases {
            timeline.set(layer, "opacity", times: [0], scalars: [layer == .container || layer == .moon ? 1 : 0])
        }
        timeline.set(.container, "transform.scale", times: [0], scalars: [1])
        timeline.set(.moon, "position", times: [0], points: [CGPoint(x: size.width / 2, y: size.height / 2)])
        timeline.set(.moon, "transform.scale", times: [0], scalars: [1])
        timeline.set(.wordmark, "transform.translation.y", times: [0], scalars: [8])
        timeline.set(.path, "strokeEnd", times: [0], scalars: [0])
        for layer in [LayerID.sun, .halo] {
            timeline.set(layer, "transform.translation.y", times: [0], scalars: [reduceMotion ? 0 : 110])
        }
        guard !reduceMotion else { return timeline }

        for layer in [LayerID.sky, .band] {
            timeline.set(layer, "opacity", times: [0, 0.3, 1.1], scalars: [0, 0, 1], curves: [.linear, .easeOut])
        }
        for layer in [LayerID.sun, .halo] {
            timeline.set(layer, "opacity", times: [0, 0.4, 1.3], scalars: [0, 0, 1], curves: [.linear, .easeOut])
            timeline.set(
                layer, "transform.translation.y", times: [0, 0.4, 1.3], scalars: [110, 110, 0],
                curves: [.linear, .easeOut])
        }
        timeline.set(.path, "opacity", times: [0], scalars: [1])
        timeline.set(.path, "strokeEnd", times: [0, 0.5, 0.56, 1.4], scalars: [0, 0, 0.03, 1])
        let flight = FlightPath(size: size)
        timeline.set(
            .plane, "position", times: [0] + flight.positionKeyTimes, points: [flight.start] + flight.positionValues)
        timeline.set(.plane, "opacity", times: [0, 0.5, 0.56, 1.4, 1.5], scalars: [0, 0, 1, 1, 0])
        timeline.set(
            .moon, "position", times: [0, 0.3, 1.1],
            points: [
                CGPoint(x: size.width / 2, y: size.height / 2), CGPoint(x: size.width / 2, y: size.height / 2),
                CGPoint(x: size.width / 2, y: size.height / 2 - 28),
            ], curves: [.linear, .easeOut])
        timeline.set(
            .moon, "transform.scale", times: [0, 0.3, 1.1], scalars: [1, 1, 0.86], curves: [.linear, .easeOut])
        timeline.set(.wordmark, "opacity", times: [0, 1, 1.4], scalars: [0, 0, 1], curves: [.linear, .easeOut])
        timeline.set(
            .wordmark, "transform.translation.y", times: [0, 1, 1.4], scalars: [8, 8, 0], curves: [.linear, .easeOut])
        return timeline
    }

    public func sample(at time: Duration) -> [LayerID: LayerValues] {
        var result: [LayerID: LayerValues] = [:]
        for track in tracks {
            result[track.layer, default: LayerValues()].properties[track.keyPath] = track.sample(at: time)
            if track.replicaCount > 1 {
                result[track.layer, default: LayerValues()].replicaOpacities = (0..<track.replicaCount).map { index in
                    guard
                        case .scalar(let value) = track.value(
                            at: time.timeInterval - Double(index) * track.replicaDelay)
                    else { preconditionFailure("Replicas require scalar opacity") }
                    return value
                }
            }
        }
        return result
    }

    mutating func set(
        _ layer: LayerID, _ keyPath: String, times: [Double], scalars: [Double], curves: [CubicBezier]? = nil
    ) {
        replace(
            Track(
                layer: layer, keyPath: keyPath, keyTimes: times, values: scalars.map(TrackValue.scalar),
                curves: curves ?? Array(repeating: .linear, count: times.count - 1)))
    }

    mutating func set(
        _ layer: LayerID, _ keyPath: String, times: [Double], points: [CGPoint], curves: [CubicBezier]? = nil
    ) {
        replace(
            Track(
                layer: layer, keyPath: keyPath, keyTimes: times, values: points.map(TrackValue.point),
                curves: curves ?? Array(repeating: .linear, count: times.count - 1)))
    }

    mutating func replace(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.layer == track.layer && $0.keyPath == track.keyPath }) {
            tracks[index] = track
        } else {
            tracks.append(track)
        }
    }

    func withoutExit() -> Self {
        var timeline = Self.opening(size: size, reduceMotion: reduceMotion)
        for track in tracks where track.layer == .status || track.layer == .statusDot {
            timeline.replace(track)
        }
        return timeline
    }

    mutating func append(
        _ layer: LayerID, _ keyPath: String, start: Double, end: Double, value: TrackValue, curve: CubicBezier
    ) {
        let original = tracks.first { $0.layer == layer && $0.keyPath == keyPath }!
        precondition(start >= original.keyTimes.last! && end > start)
        var times = original.keyTimes
        var values = original.values
        var curves = original.curves
        if start > times.last! {
            times.append(start)
            values.append(values.last!)
            curves.append(.linear)
        }
        times.append(end)
        values.append(value)
        curves.append(curve)
        replace(Track(layer: layer, keyPath: keyPath, keyTimes: times, values: values, curves: curves))
    }
}

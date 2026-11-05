import CoreGraphics
import Foundation
import Testing

@testable import Launch

nonisolated func track(_ timeline: LaunchTimeline, _ layer: LayerID, _ key: String) throws -> LaunchTimeline.Track {
    try #require(timeline.tracks.first { $0.layer == layer && $0.keyPath == key })
}

nonisolated func scalar(_ timeline: LaunchTimeline, _ layer: LayerID, _ key: String, at time: Duration) throws -> Double
{
    let value = try #require(timeline.sample(at: time)[layer]?[key])
    guard case .scalar(let scalar) = value else {
        Issue.record("Expected scalar for \(layer).\(key)")
        return .nan
    }
    return scalar
}

nonisolated func point(_ timeline: LaunchTimeline, _ layer: LayerID, at time: Duration) throws -> CGPoint {
    let value = try #require(timeline.sample(at: time)[layer]?["position"])
    guard case .point(let point) = value else {
        Issue.record("Expected position for \(layer)")
        return CGPoint(x: Double.nan, y: Double.nan)
    }
    return point
}

nonisolated func expectUniqueTracks(_ timeline: LaunchTimeline) {
    let keys = timeline.tracks.map { $0.layer.rawValue + "." + $0.keyPath }
    #expect(Set(keys).count == keys.count)
    for track in timeline.tracks {
        #expect(track.keyTimes.count == track.values.count)
        #expect(track.curves.count == track.values.count - 1)
        #expect(zip(track.keyTimes, track.keyTimes.dropFirst()).allSatisfy { $0 < $1 })
    }
}

import AppCore
import CoreGraphics
import Foundation
import Testing

@testable import Launch

nonisolated struct WelcomeTimelineTests {
    private var size: CGSize { CGSize(width: 390, height: 844) }
    private var target: CGRect { CGRect(x: 24, y: 64, width: 28, height: 28) }
    private var opening: LaunchTimeline { .opening(size: size, reduceMotion: false) }

    @Test func everyWelcomeEndingKey() throws {
        let timeline = opening.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: target)
        let expected: [(LayerID, String, Double, Double, TrackValue, CubicBezier)] = [
            (.band, "opacity", 1.6, 2.3, .scalar(0), .easeOut),
            (.stars, "opacity", 1.7, 2.3, .scalar(0.2), .easeOut),
            (.sun, "opacity", 1.6, 2.2, .scalar(0), .easeOut),
            (.halo, "opacity", 1.6, 2.2, .scalar(0), .easeOut),
            (.sun, "transform.translation.y", 1.6, 2.2, .scalar(120), .easeOut),
            (.halo, "transform.translation.y", 1.6, 2.2, .scalar(120), .easeOut),
            (.path, "opacity", 1.6, 2, .scalar(0), .linear),
            (.wordmark, "opacity", 1.6, 1.9, .scalar(0), .easeOut),
            (.wordmark, "transform.translation.y", 1.6, 1.9, .scalar(-6), .easeOut),
            (.moon, "position", 1.6, 2.3, .point(CGPoint(x: 38, y: 78)), .easeInOut),
            (.moon, "transform.scale", 1.6, 2.3, .scalar(28.0 / 104), .easeInOut),
            (.container, "opacity", 2.3, 2.55, .scalar(0), .easeOut),
        ]
        for (layer, key, start, end, value, curve) in expected {
            let actual = try track(timeline, layer, key)
            #expect(abs(actual.keyTimes[actual.keyTimes.count - 2] - start) < 1e-12)
            #expect(abs(actual.keyTimes.last! - end) < 1e-12)
            #expect(actual.values.last == value)
            #expect(actual.curves.last == curve)
        }
        #expect(try track(timeline, .container, "transform.scale").values == [.scalar(1)])
        expectUniqueTracks(timeline)
    }

    @Test func flightUsesOneStraightLineAndProgressForPositionAndScale() throws {
        let timeline = opening.withWelcomeExit(at: .milliseconds(1600), size: size, moonTarget: target)
        for ms in stride(from: 1600, through: 2300, by: 10) {
            let progress = CubicBezier.easeInOut.value(at: Double(ms - 1600) / 700)
            let expected = CGPoint(x: 195 + (38 - 195) * progress, y: 394 + (78 - 394) * progress)
            let actual = try point(timeline, .moon, at: .milliseconds(ms))
            #expect(hypot(actual.x - expected.x, actual.y - expected.y) < 0.01)
            #expect(
                abs(
                    try scalar(timeline, .moon, "transform.scale", at: .milliseconds(ms))
                        - (0.86 + (28.0 / 104 - 0.86) * progress)) < 1e-10)
        }
        #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(2300)) == 1)
        #expect(abs(try scalar(timeline, .container, "opacity", at: .milliseconds(2425)) - (1 - 0.6846431874)) < 1e-9)
        #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(2550)) < 1e-12)
    }

    @Test func targetCanChangeBeforeFlightWithoutDamagingTheOpening() throws {
        let timeline = opening.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: target)
        for original in opening.tracks {
            let merged = try track(timeline, original.layer, original.keyPath)
            #expect(Array(merged.keyTimes.prefix(original.keyTimes.count)) == original.keyTimes)
            #expect(Array(merged.values.prefix(original.values.count)) == original.values)
            #expect(Array(merged.curves.prefix(original.curves.count)) == original.curves)
        }
        for ms in stride(from: 0, through: 1600, by: 10) {
            #expect(timeline.sample(at: .milliseconds(ms)) == opening.sample(at: .milliseconds(ms)))
        }
        let moved = CGRect(x: 71, y: 109, width: 42, height: 42)
        let rebuilt = timeline.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: moved)
        #expect(rebuilt == opening.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: moved))
        #expect(rebuilt.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: moved) == rebuilt)
        #expect(try point(rebuilt, .moon, at: .milliseconds(2300)) == CGPoint(x: moved.midX, y: moved.midY))
        #expect(abs(try scalar(rebuilt, .moon, "transform.scale", at: .milliseconds(2300)) - moved.width / 104) < 1e-12)
        #expect(rebuilt.sample(at: .milliseconds(700)) == opening.sample(at: .milliseconds(700)))
    }

    @Test func lateResolutionShiftsTheEntireEndingAndRetainsStatus() throws {
        let timeline = opening.withStatus(at: .seconds(2)).withWelcomeExit(
            at: .seconds(4), size: size, moonTarget: target)
        #expect(try point(timeline, .moon, at: .seconds(4)) == CGPoint(x: 195, y: 394))
        let landed = try point(timeline, .moon, at: .milliseconds(4700))
        #expect(abs(landed.x - 38) < 0.01 && abs(landed.y - 78) < 0.01)
        #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(4950)) == 0)
        #expect(try scalar(timeline, .status, "opacity", at: .milliseconds(4900)) == 1)
        expectUniqueTracks(timeline)
    }

    @Test func reduceMotionUsesOnlyTheImmediateFade() throws {
        let opening = LaunchTimeline.opening(size: size, reduceMotion: true)
        let timeline = opening.withWelcomeExit(at: .milliseconds(50), size: size, moonTarget: target)
        #expect(timeline == opening.withReadyExit(at: .milliseconds(50)))
        #expect(try point(timeline, .moon, at: .milliseconds(350)) == CGPoint(x: 195, y: 422))
        #expect(try scalar(timeline, .moon, "transform.scale", at: .milliseconds(350)) == 1)
    }
}

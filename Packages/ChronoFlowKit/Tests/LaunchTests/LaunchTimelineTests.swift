import AppCore
import CoreGraphics
import Foundation
import Testing

@testable import Launch

nonisolated struct LaunchTimelineTests {
    private var size: CGSize { CGSize(width: 390, height: 844) }

    @Test func everyOpeningScalarKeyAndCurve() throws {
        let timeline = LaunchTimeline.opening(size: size, reduceMotion: false)
        let expected: [(LayerID, String, [Double], [Double], [CubicBezier])] = [
            (.container, "opacity", [0], [1], []),
            (.container, "transform.scale", [0], [1], []),
            (.sky, "opacity", [0, 0.3, 1.1], [0, 0, 1], [.linear, .easeOut]),
            (.band, "opacity", [0, 0.3, 1.1], [0, 0, 1], [.linear, .easeOut]),
            (.sun, "opacity", [0, 0.4, 1.3], [0, 0, 1], [.linear, .easeOut]),
            (.halo, "opacity", [0, 0.4, 1.3], [0, 0, 1], [.linear, .easeOut]),
            (.sun, "transform.translation.y", [0, 0.4, 1.3], [110, 110, 0], [.linear, .easeOut]),
            (.halo, "transform.translation.y", [0, 0.4, 1.3], [110, 110, 0], [.linear, .easeOut]),
            (.path, "opacity", [0], [1], []),
            (.path, "strokeEnd", [0, 0.5, 0.56, 1.4], [0, 0, 0.03, 1], [.linear, .linear, .linear]),
            (.plane, "opacity", [0, 0.5, 0.56, 1.4, 1.5], [0, 0, 1, 1, 0], [.linear, .linear, .linear, .linear]),
            (.moon, "opacity", [0], [1], []),
            (.moon, "transform.scale", [0, 0.3, 1.1], [1, 1, 0.86], [.linear, .easeOut]),
            (.wordmark, "opacity", [0, 1, 1.4], [0, 0, 1], [.linear, .easeOut]),
            (.wordmark, "transform.translation.y", [0, 1, 1.4], [8, 8, 0], [.linear, .easeOut]),
            (.status, "opacity", [0], [0], []),
            (.statusDot, "opacity", [0], [0], []),
        ]
        for (layer, key, times, values, curves) in expected {
            let actual = try track(timeline, layer, key)
            #expect(actual.keyTimes == times)
            #expect(actual.values == values.map(TrackValue.scalar))
            #expect(actual.curves == curves)
        }
        #expect(timeline.tracks.count == expected.count + 2)
        #expect(Set(timeline.sample(at: .zero).keys) == Set(LayerID.allCases))
        let moon = try track(timeline, .moon, "position")
        #expect(moon.keyTimes == [0, 0.3, 1.1])
        #expect(
            moon.values == [
                .point(CGPoint(x: 195, y: 422)), .point(CGPoint(x: 195, y: 422)), .point(CGPoint(x: 195, y: 394)),
            ])
        #expect(moon.curves == [.linear, .easeOut])
        let plane = try track(timeline, .plane, "position")
        let flight = FlightPath(size: size)
        #expect(plane.keyTimes == [0] + flight.positionKeyTimes)
        #expect(plane.values == ([flight.start] + flight.positionValues).map(TrackValue.point))
        #expect(plane.curves.allSatisfy { $0 == .linear })
        #expect(timeline.tracks.allSatisfy { $0.repeatInterval == nil })
        expectUniqueTracks(timeline)
    }

    @Test func samplesAtAllSpecifiedOpeningTimes() throws {
        let timeline = LaunchTimeline.opening(size: size, reduceMotion: false)
        for (milliseconds, moonY, moonScale, sky, word, plane, sun) in [
            (0, 422.0, 1.0, 0.0, 0.0, 0.0, 0.0),
            (300, 422, 1, 0, 0, 0, 0),
            (700, 402.829990752, 0.9041499538, 0.6846431874, 0, 1, 0.4883490027),
            (1100, 394, 0.86, 1, 0.3781381308, 1, 0.9245001910),
            (1400, 394, 0.86, 1, 1, 1, 1),
            (1500, 394, 0.86, 1, 1, 0, 1),
        ] {
            let time = Duration.milliseconds(milliseconds)
            #expect(abs(try point(timeline, .moon, at: time).y - moonY) < 1e-6)
            #expect(abs(try scalar(timeline, .moon, "transform.scale", at: time) - moonScale) < 1e-6)
            #expect(abs(try scalar(timeline, .sky, "opacity", at: time) - sky) < 1e-6)
            #expect(abs(try scalar(timeline, .band, "opacity", at: time) - sky) < 1e-6)
            #expect(abs(try scalar(timeline, .wordmark, "opacity", at: time) - word) < 1e-6)
            #expect(abs(try scalar(timeline, .wordmark, "transform.translation.y", at: time) - 8 * (1 - word)) < 1e-6)
            for layer in [LayerID.sun, .halo] {
                #expect(abs(try scalar(timeline, layer, "opacity", at: time) - sun) < 1e-6)
                #expect(abs(try scalar(timeline, layer, "transform.translation.y", at: time) - 110 * (1 - sun)) < 1e-6)
            }
            #expect(try scalar(timeline, .container, "opacity", at: time) == 1)
            #expect(try scalar(timeline, .container, "transform.scale", at: time) == 1)
            #expect(try scalar(timeline, .plane, "opacity", at: time) == plane)
            #expect(try scalar(timeline, .status, "opacity", at: time) == 0)
        }
        #expect(timeline.sample(at: .milliseconds(-10)) == timeline.sample(at: .zero))
        #expect(timeline.sample(at: .seconds(20)) == timeline.sample(at: .milliseconds(1500)))
        #expect(abs(try scalar(timeline, .plane, "opacity", at: .milliseconds(530)) - 0.5) < 1e-12)
        #expect(abs(try scalar(timeline, .plane, "opacity", at: .milliseconds(1450)) - 0.5) < 1e-12)
    }

    @Test func sampledPlaneFollowsStrokeEvery10Milliseconds() throws {
        for size in [self.size, CGSize(width: 375, height: 667), CGSize(width: 590, height: 900)] {
            let timeline = LaunchTimeline.opening(size: size, reduceMotion: false)
            let path = FlightPath(size: size)
            let vertices = path.positionValues
            var distances = [0.0]
            for (start, end) in zip(vertices, vertices.dropFirst()) {
                distances.append(distances.last! + hypot(end.x - start.x, end.y - start.y))
            }
            for ms in stride(from: 0, through: 1500, by: 10) {
                let time = Duration.milliseconds(ms)
                let fraction = try scalar(timeline, .path, "strokeEnd", at: time)
                #expect(abs(fraction - FlightPath.fraction(at: time)) < 1e-12)
                let tip = path.point(atFraction: fraction)
                let plane = try point(timeline, .plane, at: time)
                #expect(hypot(plane.x - tip.x, plane.y - tip.y) < 0.02)
                let distance = fraction * distances.last!
                let upper = distances.firstIndex { $0 >= distance } ?? (distances.count - 1)
                let lower = max(0, upper - 1)
                let span = distances[upper] - distances[lower]
                let progress = span == 0 ? 0 : (distance - distances[lower]) / span
                let strokeTip = CGPoint(
                    x: vertices[lower].x + (vertices[upper].x - vertices[lower].x) * progress,
                    y: vertices[lower].y + (vertices[upper].y - vertices[lower].y) * progress)
                #expect(hypot(plane.x - strokeTip.x, plane.y - strokeTip.y) < 0.02)
            }
        }
    }

    @Test func reduceMotionHoldsOnlyTheLaunchFrame() throws {
        let timeline = LaunchTimeline.opening(size: size, reduceMotion: true)
        for ms in [0, 300, 700, 1100, 1400, 1500, 8000] {
            #expect(timeline.sample(at: .milliseconds(ms)) == timeline.sample(at: .zero))
            for layer in LayerID.allCases {
                #expect(
                    try scalar(timeline, layer, "opacity", at: .milliseconds(ms))
                        == (layer == .container || layer == .moon ? 1 : 0))
            }
        }
        #expect(try point(timeline, .moon, at: .zero) == CGPoint(x: 195, y: 422))
        #expect(try scalar(timeline, .moon, "transform.scale", at: .zero) == 1)
        #expect(timeline.tracks.allSatisfy { $0.keyTimes == [0] })
        expectUniqueTracks(timeline)
    }

    @Test func pureValuesAreUsableOffTheMainActor() async {
        let result = await Task.detached {
            LaunchTimeline.opening(size: CGSize(width: 427, height: 911), reduceMotion: false).sample(
                at: .milliseconds(700))
        }.value
        #expect(result[.moon]?["opacity"] == .scalar(1))
    }
}

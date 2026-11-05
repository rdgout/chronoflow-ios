import AppCore
import CoreGraphics
import Foundation
import Testing

@testable import Launch

nonisolated struct ReadyTimelineTests {
    private var opening: LaunchTimeline { .opening(size: CGSize(width: 390, height: 844), reduceMotion: false) }

    @Test func readyExitKeysAndNeverCutShort() throws {
        for ready in [0, 50, 1499, 1500, 4600, 8000] {
            let timeline = opening.withReadyExit(at: .milliseconds(ready))
            let start = max(1.5, Double(ready) / 1000)
            for (key, end) in [("opacity", 0.0), ("transform.scale", 1.08)] {
                let actual = try track(timeline, .container, key)
                #expect(actual.keyTimes == [0, start, start + 0.4])
                #expect(actual.values == [.scalar(1), .scalar(1), .scalar(end)])
                #expect(actual.curves == [.linear, .easeOut])
            }
            let midpoint = Duration.seconds(start + 0.2)
            #expect(abs(try scalar(timeline, .container, "opacity", at: midpoint) - (1 - 0.6846431874)) < 1e-9)
            #expect(
                abs(try scalar(timeline, .container, "transform.scale", at: midpoint) - (1 + 0.08 * 0.6846431874))
                    < 1e-9)
            #expect(try scalar(timeline, .container, "opacity", at: .seconds(start + 1)) == 0)
            expectUniqueTracks(timeline)
        }
    }

    @Test func mergingReadyPreservesEveryOpeningKeyAndSample() {
        let timeline = opening.withReadyExit(at: .milliseconds(1500))
        for original in opening.tracks {
            let merged = timeline.tracks.first { $0.layer == original.layer && $0.keyPath == original.keyPath }!
            #expect(Array(merged.keyTimes.prefix(original.keyTimes.count)) == original.keyTimes)
            #expect(Array(merged.values.prefix(original.values.count)) == original.values)
            #expect(Array(merged.curves.prefix(original.curves.count)) == original.curves)
        }
        for ms in stride(from: 0, through: 1500, by: 10) {
            #expect(timeline.sample(at: .milliseconds(ms)) == opening.sample(at: .milliseconds(ms)))
        }
        #expect(timeline.sample(at: .milliseconds(700)) == opening.sample(at: .milliseconds(700)))
        #expect(timeline.withReadyExit(at: .milliseconds(1500)) == timeline)
        #expect(timeline.withReadyExit(at: .milliseconds(4600)) == opening.withReadyExit(at: .milliseconds(4600)))
    }

    @Test func slowStatusFadeAndLatchThroughExit() throws {
        let timeline = opening.withStatus(at: .seconds(2)).withReadyExit(at: .milliseconds(4600))
        let status = try track(timeline, .status, "opacity")
        #expect(status.keyTimes == [0, 2, 2.3])
        #expect(status.values == [.scalar(0), .scalar(0), .scalar(1)])
        #expect(status.curves == [.linear, .easeOut])
        #expect(try scalar(timeline, .status, "opacity", at: .milliseconds(1999)) == 0)
        #expect(abs(try scalar(timeline, .status, "opacity", at: .milliseconds(2150)) - 0.6846431874) < 1e-9)
        for ms in [2300, 2600, 4600, 4900, 5000, 9000] {
            #expect(try scalar(timeline, .status, "opacity", at: .milliseconds(ms)) == 1)
        }
        #expect(opening.withReadyExit(at: .milliseconds(4600)).withStatus(at: .seconds(2)) == timeline)
        #expect(timeline.withStatus(at: .seconds(2)) == timeline)
        expectUniqueTracks(timeline)
    }

    @Test func dotsRepeatFromMountWithDelayedReplicas() throws {
        let timeline = opening.withStatus(at: .seconds(2))
        let dots = try track(timeline, .statusDot, "opacity")
        #expect(dots.keyTimes == [0, 0.48, 0.96, 1.2])
        #expect(dots.values == [.scalar(0.25), .scalar(1), .scalar(0.25), .scalar(0.25)])
        #expect(dots.curves == [.easeInOut, .easeInOut, .linear])
        #expect(dots.repeatInterval == 1.2)
        #expect(dots.replicaCount == 3)
        #expect(dots.replicaDelay == 0.2)
        for cycle in 0..<8 {
            for replica in 0..<3 {
                let delay = Double(cycle) * 1.2 + Double(replica) * 0.2
                for (offset, expected) in [
                    (0.0, 0.25), (0.24, 0.625), (0.48, 1), (0.72, 0.625), (0.96, 0.25), (1.1, 0.25),
                ] {
                    let sample = try #require(timeline.sample(at: .seconds(delay + offset))[.statusDot])
                    #expect(sample.replicaOpacities.count == 3)
                    #expect(abs(sample.replicaOpacities[replica] - expected) < 1e-9)
                }
            }
        }
        let early = opening.withStatus(at: .seconds(1))
        #expect(
            early.sample(at: .milliseconds(2600))[.statusDot] == timeline.sample(at: .milliseconds(2600))[.statusDot])
        for original in opening.tracks where original.layer != .status && original.layer != .statusDot {
            #expect(timeline.tracks.contains(original))
        }
    }

    @Test func reduceMotionFadesImmediatelyWithConstantDots() throws {
        let opening = LaunchTimeline.opening(size: CGSize(width: 375, height: 667), reduceMotion: true)
        let timeline = opening.withStatus(at: .seconds(2)).withReadyExit(at: .milliseconds(50))
        let exit = try track(timeline, .container, "opacity")
        #expect(exit.keyTimes == [0, 0.05, 0.35])
        #expect(exit.curves == [.linear, .easeOut])
        #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(350)) == 0)
        #expect(try scalar(timeline, .container, "transform.scale", at: .seconds(4)) == 1)
        for ms in [0, 480, 2000, 2300, 2600, 8000] {
            #expect(timeline.sample(at: .milliseconds(ms))[.statusDot]?.replicaOpacities == [1, 1, 1])
            #expect(try point(timeline, .moon, at: .milliseconds(ms)) == CGPoint(x: 187.5, y: 333.5))
        }
        #expect(try track(timeline, .statusDot, "opacity").repeatInterval == nil)
        #expect(try scalar(timeline, .status, "opacity", at: .milliseconds(2300)) == 1)
        let immediate = opening.withReadyExit(at: .zero)
        #expect(try track(immediate, .container, "opacity").keyTimes == [0, 0.3])
        #expect(try track(opening.withStatus(at: .zero), .status, "opacity").keyTimes == [0, 0.3])
        expectUniqueTracks(timeline)
    }
}

import AppCore
import CoreGraphics
import Launch
import Testing

@Suite struct LaunchSnapshotCoverageTests {
    @Test func requiredFramesAndEndings() throws {
        #expect(
            LaunchSnapshotCase.all.map(\.name) == [
                "ready-0", "ready-700", "ready-1400", "ready-1700", "ready-1900", "slow-2600", "slow-4900",
                "welcome-1500", "welcome-1950", "welcome-2400", "reduceMotion-0",
            ])
        let size = CGSize(width: 430, height: 932)
        let insets = MoonTarget.Insets(top: 62, left: 19, bottom: 34, right: 31)
        for frame in LaunchSnapshotCase.all {
            let timeline = frame.timeline(size: size, safeInsets: insets)
            expectUniqueTracks(timeline)
            switch frame.mode {
            case .ready:
                #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(1500)) == 1)
                #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(1900)) == 0)
            case .slow:
                #expect(try scalar(timeline, .status, "opacity", at: .milliseconds(2600)) == 1)
                #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(4600)) == 1)
                #expect(try scalar(timeline, .container, "opacity", at: .milliseconds(5000)) == 0)
            case .welcome:
                let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: 28)
                let landing = try point(timeline, .moon, at: .milliseconds(2400))
                #expect(abs(landing.x - target.midX) < 1e-9)
                #expect(abs(landing.y - target.midY) < 1e-9)
            case .reduceMotion:
                #expect(timeline.reduceMotion)
                #expect(try scalar(timeline, .wordmark, "opacity", at: .zero) == 0)
            }
        }
    }

    @Test func statusAndPathApexRelationS1() {
        for (height, statusTop, apex) in [(844.0, 518.0, 512.5), (874, 533, 527.5)] {
            let size = CGSize(width: 390, height: height)
            let path = FlightPath(size: size)
            let middle = path.point(atFraction: 0.5)
            #expect(abs(middle.y - apex) < 0.001)
            #expect(abs(size.height / 2 + 96 - CGFloat(statusTop)) < 1e-9)
            #expect(abs(statusTop - middle.y - 5.5) < 0.001)
        }
    }
}

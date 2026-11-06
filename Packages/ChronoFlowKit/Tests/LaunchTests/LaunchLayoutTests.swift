import AppCore
import CoreGraphics
import Testing

@testable import Launch

struct LaunchLayoutTests {
    @Test func everyD1cSizeKeepsTheBoardOffsetsAndStretchesTheBand() {
        for size in [
            CGSize(width: 375, height: 667), CGSize(width: 390, height: 844),
            CGSize(width: 402, height: 874), CGSize(width: 420, height: 912),
            CGSize(width: 440, height: 956), CGSize(width: 466, height: 678),
        ] {
            for insets in [
                MoonTarget.Insets(top: 0, left: 0, bottom: 0, right: 0),
                MoonTarget.Insets(top: 62, left: 19, bottom: 34, right: 31),
            ] {
                let layout = LaunchLayout(size: size, safeAreaInsets: insets)
                let cy = size.height / 2
                #expect(layout.moonCentre == CGPoint(x: size.width / 2, y: cy))
                #expect(layout.sunCentre.y - cy == 228)
                #expect(layout.band.minY - cy == 48)
                #expect(layout.band.maxY == size.height)
                #expect(layout.pathStart.y - cy == 218)
                #expect(layout.pathEnd.y == layout.pathStart.y)
                #expect(layout.pathControl1.y == layout.band.minY)
                #expect(layout.pathControl2.y == layout.band.minY)
                #expect(layout.wordmarkCentre.y - cy == 60)
                #expect(layout.status.minY - cy == 96)
                #expect(layout.safeBounds.minX == insets.left)
                #expect(layout.safeBounds.maxX == size.width - insets.right)
                #expect(layout.safeBounds.minY == insets.top)
                #expect(layout.safeBounds.maxY == size.height - insets.bottom)
                let timeline = LaunchTimeline.opening(size: size, reduceMotion: false)
                for time in stride(from: 500, through: 1400, by: 10) {
                    let plane = timeline.sample(at: .milliseconds(time))[.plane]?["position"]
                    let board = LaunchTimeline.opening(
                        size: CGSize(width: size.width, height: 844), reduceMotion: false)
                    let reference = board.sample(at: .milliseconds(time))[.plane]?["position"]
                    guard case .point(let actual) = plane, case .point(let expected) = reference else {
                        Issue.record("Missing plane position")
                        continue
                    }
                    #expect(abs(actual.x - expected.x) < 1e-8)
                    #expect(abs(actual.y - cy - (expected.y - 422)) < 1e-8)
                }
            }
        }
    }

    @Test func board844GeometryIsExactlyTheOriginalComposition() {
        let layout = LaunchLayout(size: CGSize(width: 390, height: 844))
        #expect(layout.moonCentre == CGPoint(x: 195, y: 422))
        #expect(layout.sunCentre == CGPoint(x: 195, y: 650))
        #expect(layout.band == CGRect(x: 0, y: 470, width: 390, height: 374))
        #expect(layout.pathStart == CGPoint(x: -10, y: 640))
        #expect(layout.pathControl1 == CGPoint(x: 90, y: 470))
        #expect(layout.pathControl2 == CGPoint(x: 300, y: 470))
        #expect(layout.pathEnd == CGPoint(x: 400, y: 640))
        #expect(layout.wordmarkCentre == CGPoint(x: 195, y: 482))
        #expect(layout.status == CGRect(x: 0, y: 518, width: 390, height: 20))
    }
}

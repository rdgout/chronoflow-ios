import AppCore
import CoreGraphics
import Launch
import Testing

struct LaunchSnapshotGeometryTests {
    @Test func sampledSunHasSubstantialVisibleHeightOnEveryD1cSize() throws {
        for size in [
            CGSize(width: 375, height: 667), CGSize(width: 390, height: 844),
            CGSize(width: 402, height: 874), CGSize(width: 420, height: 912),
            CGSize(width: 440, height: 956), CGSize(width: 466, height: 678),
        ] {
            let layout = LaunchLayout(size: size)
            let insets = MoonTarget.Insets(top: 62, left: 19, bottom: 34, right: 31)
            let safe = CGRect(x: insets.left, y: 0, width: size.width - insets.left - insets.right, height: size.height)
            for frame in LaunchSnapshotCase.all {
                let timeline = frame.timeline(size: size, safeInsets: insets)
                let time = Duration.milliseconds(frame.milliseconds)
                guard try scalar(timeline, .sun, "opacity", at: time) > 0,
                    try scalar(timeline, .container, "opacity", at: time) > 0
                else { continue }
                let translation = try scalar(timeline, .sun, "transform.translation.y", at: time)
                let scale = try scalar(timeline, .container, "transform.scale", at: time)
                let sun = CGRect(
                    x: size.width / 2 - 90 * scale,
                    y: size.height * 0.4 + (layout.sunCentre.y + translation - 90 - size.height * 0.4) * scale,
                    width: 180 * scale, height: 180 * scale)
                #expect(LaunchSnapshotGeometry.containsSun(sun, in: safe), "\(size) \(frame.name): \(sun)")
            }
        }
    }

    @Test func sunMayCrossOnlyTheBottomWithAtLeastAThirdVisible() {
        for bounds in [
            CGRect(x: 0, y: 0, width: 375, height: 667),
            CGRect(x: 19, y: 0, width: 416, height: 678),
        ] {
            let contained = CGRect(x: bounds.midX - 90, y: bounds.maxY - 180, width: 180, height: 180)
            let horizon = contained.offsetBy(dx: 0, dy: 120)
            #expect(LaunchSnapshotGeometry.containsSun(contained, in: bounds))
            #expect(LaunchSnapshotGeometry.containsSun(horizon, in: bounds))
            #expect(!LaunchSnapshotGeometry.containsSun(horizon.offsetBy(dx: 0, dy: 1), in: bounds))
            #expect(!LaunchSnapshotGeometry.containsSun(horizon.offsetBy(dx: 0, dy: 60), in: bounds))
            for invalid in [
                CGRect(x: bounds.minX - 1, y: contained.minY, width: 180, height: 180),
                CGRect(x: bounds.maxX - 179, y: contained.minY, width: 180, height: 180),
                CGRect(x: contained.minX, y: bounds.minY - 1, width: 180, height: 180),
                CGRect.zero, .null, .infinite,
            ] {
                #expect(!LaunchSnapshotGeometry.containsSun(invalid, in: bounds))
            }
        }
    }
}

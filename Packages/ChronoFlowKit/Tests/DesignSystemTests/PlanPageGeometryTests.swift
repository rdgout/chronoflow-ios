import CoreGraphics
import DesignSystem
import SnapshotSupport
import Testing

struct PlanPageGeometryTests {
    @Test func everyProfileKeepsThePageGutterInsideItsSafeAreaWithoutDoubleInsets() throws {
        for device in try SnapshotDevice.all() {
            let window = CGRect(origin: .zero, size: device.size)
            let safe = CGRect(
                x: device.insets.left, y: device.insets.top,
                width: window.width - device.insets.left - device.insets.right,
                height: window.height - device.insets.top - device.insets.bottom)
            for frame in [window, safe] {
                let insets = PlanPageGeometry.horizontalInsets(frame: frame, safeBounds: safe)
                let left = frame.minX + insets.left + PlanUITokens.space4
                let right = frame.maxX - insets.right - PlanUITokens.space4
                #expect(left == safe.minX + PlanUITokens.space4)
                #expect(right == safe.maxX - PlanUITokens.space4)
            }
        }
    }

    @Test func railInsetsFollowWindowChangesAndEitherSide() {
        for size in [CGSize(width: 466, height: 678), CGSize(width: 669, height: 678)] {
            let window = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
            for left in [CGFloat(0), 19] {
                let right: CGFloat = left == 0 ? 19 : 0
                let safe = CGRect(
                    x: window.minX + left, y: window.minY, width: window.width - left - right,
                    height: window.height)
                let insets = PlanPageGeometry.horizontalInsets(frame: window, safeBounds: safe)
                #expect(insets.left == left)
                #expect(insets.right == right)
                let consumed = PlanPageGeometry.horizontalInsets(frame: safe, safeBounds: safe)
                #expect(consumed.left == 0)
                #expect(consumed.right == 0)
            }
        }
    }
}

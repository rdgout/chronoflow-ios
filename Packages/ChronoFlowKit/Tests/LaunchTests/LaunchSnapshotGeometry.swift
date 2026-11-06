import CoreGraphics

nonisolated enum LaunchSnapshotGeometry {
    static func containsSun(_ rect: CGRect, in bounds: CGRect) -> Bool {
        guard !rect.isEmpty, !rect.isInfinite, !rect.isNull else { return false }
        let visibleHeight = max(0, min(rect.maxY, bounds.maxY) - max(rect.minY, bounds.minY))
        return rect.minX >= bounds.minX - 0.5 && rect.maxX <= bounds.maxX + 0.5
            && rect.minY >= bounds.minY - 0.5 && rect.minY < bounds.maxY
            && visibleHeight >= rect.height / 3
    }
}

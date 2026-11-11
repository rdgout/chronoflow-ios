import CoreGraphics

public nonisolated enum ScrollReachability {
    public static func reveal(
        _ frame: CGRect, viewport: CGRect, currentOffset: CGFloat, minimumOffset: CGFloat, maximumOffset: CGFloat
    ) -> (offset: CGFloat, frame: CGRect, fits: Bool) {
        let delta = frame.minY < viewport.minY ? frame.minY - viewport.minY : max(0, frame.maxY - viewport.maxY)
        let offset = min(maximumOffset, max(minimumOffset, currentOffset + delta))
        let revealed = frame.offsetBy(dx: 0, dy: currentOffset - offset)
        let valid =
            [frame, viewport].allSatisfy {
                !$0.isEmpty && !$0.isNull && !$0.isInfinite
                    && [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy(\.isFinite)
            } && [currentOffset, minimumOffset, maximumOffset].allSatisfy(\.isFinite)
            && minimumOffset <= maximumOffset
        return (offset, revealed, valid && viewport.contains(revealed))
    }
}

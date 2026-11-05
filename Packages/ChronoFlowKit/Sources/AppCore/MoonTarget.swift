import CoreGraphics
import Foundation

public enum MoonTarget {
    public struct Insets: Sendable, Equatable {
        public let top: CGFloat
        public let left: CGFloat
        public let bottom: CGFloat
        public let right: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            precondition([top, left, bottom, right].allSatisfy { $0.isFinite && $0 >= 0 })
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
    }

    public static func fallback(size: CGSize, safeAreaInsets: Insets, rowHeight: CGFloat) -> CGRect {
        precondition(rowHeight.isFinite && rowHeight > 0)
        let content = contentBounds(size: size, safeAreaInsets: safeAreaInsets)
        return CGRect(x: content.minX, y: content.minY + max(28, rowHeight) / 2 - 14, width: 28, height: 28)
    }

    public static func contentBounds(size: CGSize, safeAreaInsets: Insets) -> CGRect {
        precondition(size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0)
        let top = max(safeAreaInsets.top + 16, 64)
        let bottom = max(safeAreaInsets.bottom, 40)
        return CGRect(
            x: safeAreaInsets.left + 24, y: top,
            width: max(0, size.width - safeAreaInsets.left - safeAreaInsets.right - 48),
            height: max(0, size.height - top - bottom))
    }
}

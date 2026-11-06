import CoreGraphics
import DesignSystem

nonisolated public enum AuthLayout {
    public struct Insets: Equatable, Sendable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat
        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }
    }
    public static func content(size: CGSize, insets: Insets) -> CGRect {
        CGRect(
            x: insets.left + AuthTokens.gutter, y: insets.top + AuthTokens.gutter,
            width: max(0, size.width - insets.left - insets.right - AuthTokens.gutter * 2),
            height: max(0, size.height - insets.top - insets.bottom - AuthTokens.gutter - AuthTokens.bottom))
    }

    public static func reveal(field: CGRect, submit: CGRect, viewport: CGRect) -> (offset: CGFloat, fits: Bool) {
        let pair = field.union(submit)
        let fits = pair.height <= viewport.height
        let offset = max(pair.maxY - viewport.maxY, min(0, pair.minY - viewport.minY))
        return (fits ? offset : field.minY - viewport.minY, fits)
    }
}

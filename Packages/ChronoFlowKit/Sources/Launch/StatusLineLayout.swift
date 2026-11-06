import Foundation

nonisolated public struct StatusLineLayout: Sendable, Equatable {
    public let text: CGRect
    public let dots: CGRect
    public var ink: CGRect { text.union(dots) }

    public init(
        width: CGFloat, textWidth: CGFloat, ascent: CGFloat, descent: CGFloat, lineHeight: CGFloat, scale: CGFloat
    ) {
        let roundedWidth = ceil(textWidth * scale) / scale
        let left = (width - roundedWidth - 6 - 18) / 2
        text = CGRect(x: left, y: (lineHeight - ascent - descent) / 2, width: roundedWidth, height: lineHeight)
        dots = CGRect(x: left + roundedWidth + 6, y: 0, width: 18, height: lineHeight)
    }
}

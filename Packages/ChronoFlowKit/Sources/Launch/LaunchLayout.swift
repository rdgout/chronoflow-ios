import AppCore
import CoreGraphics

nonisolated public struct LaunchLayout: Sendable, Equatable {
    public let bounds: CGRect
    public let safeBounds: CGRect
    public let moonCentre: CGPoint
    public let sunCentre: CGPoint
    public let band: CGRect
    public let wordmarkCentre: CGPoint
    public let status: CGRect
    public let pathStart: CGPoint
    public let pathControl1: CGPoint
    public let pathControl2: CGPoint
    public let pathEnd: CGPoint

    public init(size: CGSize, safeAreaInsets: MoonTarget.Insets = .init(top: 0, left: 0, bottom: 0, right: 0)) {
        precondition(size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite)
        bounds = CGRect(origin: .zero, size: size)
        safeBounds = CGRect(
            x: safeAreaInsets.left, y: safeAreaInsets.top,
            width: max(0, size.width - safeAreaInsets.left - safeAreaInsets.right),
            height: max(0, size.height - safeAreaInsets.top - safeAreaInsets.bottom))
        let cy = size.height / 2
        func boardY(bottomOffset: CGFloat) -> CGFloat { cy + (844 / 2 - bottomOffset) }
        moonCentre = CGPoint(x: size.width / 2, y: cy)
        sunCentre = CGPoint(x: size.width / 2, y: boardY(bottomOffset: 194))
        let bandTop = boardY(bottomOffset: 374)
        band = CGRect(x: 0, y: bandTop, width: size.width, height: size.height - bandTop)
        wordmarkCentre = CGPoint(x: size.width / 2, y: cy + 60)
        status = CGRect(x: 0, y: cy + 96, width: size.width, height: 20)
        pathStart = CGPoint(x: -10, y: boardY(bottomOffset: 204))
        pathControl1 = CGPoint(x: 90 * size.width / 390, y: bandTop)
        pathControl2 = CGPoint(x: 300 * size.width / 390, y: bandTop)
        pathEnd = CGPoint(x: size.width + 10, y: pathStart.y)
    }
}

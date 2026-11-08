import AppCore
import DesignSystem
import Foundation

public struct TermsGeometry: Sendable, Equatable {
    public let content: CGRect
    public let top: CGFloat
    public let bottom: CGFloat
    public let leading: CGFloat
    public let trailing: CGFloat

    public init(size: CGSize, insets: MoonTarget.Insets) {
        top = insets.top + PlanUITokens.space6
        bottom = insets.bottom + PlanUITokens.space8
        leading = insets.left + PlanUITokens.space4
        trailing = insets.right + PlanUITokens.space4
        content = CGRect(
            x: leading, y: top, width: max(0, size.width - leading - trailing),
            height: max(0, size.height - top - bottom))
    }
}

import SwiftUI

extension Typography.Style {
    public func planTextIdentifier(color: ColorToken, context: String? = nil) -> String {
        "plan.text.\(color.rawValue).\(face.rawValue).\(size)" + (context.map { "|\($0)" } ?? "")
    }
}

extension View {
    @ViewBuilder public func planTextStyle(
        _ style: Typography.Style, color: ColorToken? = nil, context: String? = nil
    ) -> some View {
        if let color {
            font(style.font).foregroundStyle(color.color)
                .accessibilityIdentifier(style.planTextIdentifier(color: color, context: context))
        } else {
            font(style.font).accessibilityIdentifier(style.planTextIdentifier(color: .foreground, context: context))
        }
    }
}

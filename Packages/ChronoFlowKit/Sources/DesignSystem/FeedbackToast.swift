#if canImport(UIKit)
    import SwiftUI

    public struct FeedbackToast: View {
        @Environment(\.colorScheme) private var scheme
        let title: String
        let identifier: String
        var success = true
        public init(title: String, identifier: String, success: Bool = true) {
            self.title = title
            self.identifier = identifier
            self.success = success
        }
        public var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                if success {
                    Image(systemName: "checkmark").font(Typography.screenLabel.font)
                        .frame(width: PlanUITokens.space6, height: PlanUITokens.space6)
                        .background(ColorToken.dawn.color, in: Circle()).foregroundStyle(
                            ColorToken.dawnForeground.color
                        )
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "exclamationmark.circle").font(Typography.screenBodyLg.font)
                        .foregroundStyle(ColorToken.destructive.color).accessibilityHidden(true)
                }
                WelcomeText(title, style: Typography.screenBody, color: .popoverForeground).accessibilityIdentifier(
                    identifier
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space3)
            .frame(minHeight: SettingsTokens.toastHeight)
            .background(ColorToken.popover.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl))
            .foregroundStyle(ColorToken.popoverForeground.color)
            .overlay {
                RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl)
                    .strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
            }.background {
                RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                    .inset(by: -(scheme == .dark ? AuthTokens.darkShadowSpread : AuthTokens.lightShadowSpread))
                    .fill(ColorToken.card.color)
                    .shadow(
                        color: ColorToken.authShadow.color,
                        radius: scheme == .dark ? AuthTokens.darkShadowRadius : AuthTokens.lightShadowRadius,
                        y: scheme == .dark ? AuthTokens.darkShadowY : AuthTokens.lightShadowY)
            }
            .padding(.horizontal, PlanUITokens.space4).padding(.bottom, PlanUITokens.space6).planPageRail()
            .frame(maxWidth: .infinity).planPageSafeArea()
        }
    }

#endif

import SwiftUI

#if canImport(UIKit)
    public struct WelcomeButton: View {
        public enum Kind { case primary, secondary }
        private let title: String
        private let kind: Kind
        private let action: () -> Void

        public init(_ title: String, kind: Kind, action: @escaping () -> Void) {
            self.title = title
            self.kind = kind
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                WelcomeText(title, style: kind == .primary ? Typography.primaryButton : Typography.secondaryButton)
                    .multilineTextAlignment(.center)
                    .foregroundStyle((kind == .primary ? ColorToken.dawnForeground : .skyCopy).color)
                    .padding(.horizontal, WelcomeTokens.cardHorizontalPadding)
                    .padding(.vertical, WelcomeTokens.brandGap)
                    .frame(maxWidth: .infinity, minHeight: WelcomeTokens.buttonHeight)
                    .background((kind == .primary ? ColorToken.dawn : .skyCopyBackground).color, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }
#endif

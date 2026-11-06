import DesignSystem
import SwiftUI

#if canImport(UIKit)
    public struct WelcomeBrand: View {
        @Environment(\.locale) private var locale

        public init() {}

        public var body: some View {
            HStack(spacing: WelcomeTokens.brandGap) {
                MoonShape()
                    .stroke(
                        ColorToken.dawn.color,
                        style: StrokeStyle(
                            lineWidth: WelcomeTokens.moonStroke * WelcomeTokens.moonSize / WelcomeTokens.moonViewBox,
                            lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: WelcomeTokens.moonSize, height: WelcomeTokens.moonSize)
                    .accessibilityHidden(true)
                WelcomeText(WelcomeCopy.string("ChronoFlow", locale: locale), style: Typography.welcomeWordmark)
                    .foregroundStyle(ColorToken.skyTitle.color)
                    .accessibilityIdentifier("welcome.wordmark")
            }
        }
    }
#endif

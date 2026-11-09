import AppCore
import DesignSystem
import SwiftUI

#if canImport(UIKit)
    public struct WelcomeBrand: View {
        @Environment(\.locale) private var locale
        @Environment(\.moonAnchorStore) private var moonAnchorStore

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
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .global)
                    } action: {
                        moonAnchorStore?.update($0)
                    }
                    .accessibilityHidden(true)
                WelcomeText(
                    WelcomeCopy.string("ChronoFlow", locale: locale), style: Typography.welcomeWordmark,
                    color: .skyTitle
                )
                .accessibilityIdentifier("welcome.wordmark")
                .modifier(IntroItem(index: 0))
            }
        }
    }
#endif

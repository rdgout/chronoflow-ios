#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    public struct AuthBrand: View {
        @Environment(\.locale) private var locale
        let back: () -> Void
        public init(back: @escaping () -> Void) { self.back = back }
        public var body: some View {
            HStack(spacing: 0) {
                Button(action: back) {
                    AuthGlyph.back.image.resizable().frame(width: AuthTokens.backGlyph, height: AuthTokens.backGlyph)
                        .frame(width: AuthTokens.touch, height: AuthTokens.touch).contentShape(Circle())
                }
                .foregroundStyle(ColorToken.skyTitle.color).buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: AuthCopy.string("Back", locale: locale))).accessibilityIdentifier(
                    "auth.back")
                Spacer(minLength: 0)
                HStack(spacing: AuthTokens.brandGap) {
                    MoonShape().stroke(
                        ColorToken.dawn.color,
                        style: StrokeStyle(
                            lineWidth: WelcomeTokens.moonStroke * AuthTokens.moon / WelcomeTokens.moonViewBox,
                            lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: AuthTokens.moon, height: AuthTokens.moon).accessibilityHidden(true)
                    WelcomeText(
                        AuthCopy.string("ChronoFlow", locale: locale), style: Typography.authBrand, color: .skyTitle)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("auth.brand")
                Spacer(minLength: 0)
                Color.clear.frame(width: AuthTokens.touch, height: AuthTokens.touch).accessibilityHidden(true)
            }.frame(minHeight: AuthTokens.touch)
        }
    }
#endif

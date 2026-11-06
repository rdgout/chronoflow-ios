import AppCore
import DesignSystem
import SwiftUI

#if canImport(UIKit)
    public struct WelcomeView: View {
        @Environment(\.locale) private var locale
        @Environment(\.launchIntro) private var launchIntro
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.forcesReduceMotion) private var forcesReduceMotion
        @Environment(\.welcomeNavigator) private var navigator
        @State private var activeIntro: LaunchIntro?
        @State private var initialized = false
        private var onFrame: (@MainActor (WelcomeElement, CGRect) -> Void)?

        public init() {}

        init(onFrame: @escaping @MainActor (WelcomeElement, CGRect) -> Void) { self.onFrame = onFrame }

        public var body: some View {
            GeometryReader { safeGeometry in
                GeometryReader { geometry in
                    let insets = safeGeometry.safeAreaInsets
                    let top = max(insets.top + WelcomeTokens.groupGap, WelcomeTokens.topPadding)
                    let bottom = max(insets.bottom, WelcomeTokens.bottomPadding)
                    ZStack {
                        CfSky()
                        PatternDots().opacity(WelcomeTokens.starsOpacity)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                heading
                                Spacer(minLength: WelcomeTokens.gutter)
                                actions
                            }
                            .frame(minHeight: max(0, geometry.size.height - top - bottom), alignment: .topLeading)
                            .padding(.top, top)
                            .padding(.bottom, bottom)
                            .padding(.leading, insets.leading + WelcomeTokens.gutter)
                            .padding(.trailing, insets.trailing + WelcomeTokens.gutter)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .ignoresSafeArea()
                .environment(\.launchIntro, activeIntro)
            }
            .environment(\.welcomeLayoutObserver, onFrame)
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if !reduceMotion && !forcesReduceMotion, launchIntro?.claim() == true { activeIntro = launchIntro }
            }
            .onDisappear { activeIntro = nil }
        }

        private var heading: some View {
            VStack(alignment: .leading, spacing: WelcomeTokens.groupGap) {
                WelcomeBrand()
                    .reportWelcomeFrame(.brand)
                WelcomeText(copy("Jet-lag planner").uppercased(with: locale), style: Typography.eyebrow)
                    .foregroundStyle(ColorToken.dawn.color)
                    .reportWelcomeFrame(.eyebrow)
                    .modifier(IntroItem(index: 1))
                    .padding(.top, WelcomeTokens.eyebrowMargin)
                    .accessibilityIdentifier("welcome.eyebrow")
                WelcomeText(copy("Plan your clock shift for your next trip"), style: Typography.headline)
                    .foregroundStyle(ColorToken.skyTitle.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("welcome.headline")
                    .reportWelcomeFrame(.headline)
                    .modifier(IntroItem(index: 2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var actions: some View {
            VStack(alignment: .leading, spacing: WelcomeTokens.actionGap) {
                WelcomeText(
                    copy(
                        "Tell us your flights and how you sleep. You get a day-by-day plan for sleep, light and caffeine that helps your body clock shift."
                    ), style: Typography.copy
                )
                .foregroundStyle(ColorToken.skyCopy.color)
                .padding(.vertical, WelcomeTokens.cardVerticalPadding)
                .padding(.horizontal, WelcomeTokens.cardHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ColorToken.skyCopyBackground.color,
                    in: RoundedRectangle(cornerRadius: WelcomeTokens.cardRadius)
                )
                .reportWelcomeFrame(.copy)
                .modifier(IntroItem(index: 3))
                .padding(.bottom, WelcomeTokens.actionGap)
                .accessibilityIdentifier("welcome.copy")
                WelcomeButton(copy("Plan my trip"), kind: .primary) { navigator?.navigate(to: .guestWizard) }
                    .accessibilityIdentifier("welcome.plan")
                    .reportWelcomeFrame(.plan)
                    .modifier(IntroItem(index: 4))
                WelcomeButton(copy("Sign in"), kind: .secondary) { navigator?.navigate(to: .signIn) }
                    .accessibilityIdentifier("welcome.signIn")
                    .reportWelcomeFrame(.signIn)
                    .modifier(IntroItem(index: 5))
            }
        }

        private func copy(_ key: String) -> String { WelcomeCopy.string(key, locale: locale) }
    }
#endif

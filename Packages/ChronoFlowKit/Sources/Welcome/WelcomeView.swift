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
        private var snapshotInsets: MoonTarget.Insets?
        private var onFrame: (@MainActor (WelcomeElement, CGRect) -> Void)?

        public init() {}

        init(safeAreaInsets: MoonTarget.Insets? = nil, onFrame: @escaping @MainActor (WelcomeElement, CGRect) -> Void) {
            snapshotInsets = safeAreaInsets
            self.onFrame = onFrame
        }

        public var body: some View {
            GeometryReader { safeGeometry in
                GeometryReader { geometry in
                    let insets = safeGeometry.safeAreaInsets
                    let layout = WelcomeGeometry(
                        size: geometry.size,
                        insets: snapshotInsets
                            ?? .init(
                                top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing))
                    ZStack {
                        CfSky()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                heading
                                Spacer(minLength: WelcomeTokens.gutter)
                                actions
                            }
                            .frame(minHeight: max(0, layout.content.height), alignment: .topLeading)
                            .padding(.top, layout.top)
                            .padding(.bottom, layout.bottom)
                            .padding(.leading, layout.leading)
                            .padding(.trailing, layout.trailing)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .ignoresSafeArea()
                .environment(\.launchIntro, presentedIntro)
            }
            .environment(\.welcomeLayoutObserver, onFrame)
            .onAppear {
                guard !initialized else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = launchIntro?.frozenTime != nil
                withTransaction(transaction) {
                    initialized = true
                    if !reduceMotion && !forcesReduceMotion, launchIntro?.claim() == true { activeIntro = launchIntro }
                }
            }
            .onDisappear { activeIntro = nil }
        }

        private var presentedIntro: LaunchIntro? {
            if initialized { return activeIntro }
            guard !reduceMotion && !forcesReduceMotion,
                let launchIntro, launchIntro.frozenTime != nil, !launchIntro.hasPlayed
            else { return nil }
            return launchIntro
        }

        private var heading: some View {
            VStack(alignment: .leading, spacing: WelcomeTokens.groupGap) {
                WelcomeBrand()
                    .reportWelcomeFrame(.brand)
                WelcomeText(copy("Jet-lag planner").uppercased(with: locale), style: Typography.eyebrow, color: .dawn)
                    .reportWelcomeFrame(.eyebrow)
                    .modifier(IntroItem(index: 1))
                    .padding(.top, WelcomeTokens.eyebrowMargin)
                    .accessibilityIdentifier("welcome.eyebrow")
                WelcomeText(
                    copy("Plan your clock shift for your next trip"), style: Typography.headline, color: .skyTitle
                )
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
                    ), style: Typography.copy, color: .skyCopy
                )
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

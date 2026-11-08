#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanUI
    import SwiftUI

    @MainActor public struct SignOutPendingSheet: View {
        private let model: SettingsHomeModel
        @State private var contentHeight: CGFloat = 0
        public init(model: SettingsHomeModel) { self.model = model }

        public var body: some View {
            SignOutPendingContent(model: model) { contentHeight = $0 }
                .presentationDragIndicator(.visible)
                .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large])
                .interactiveDismissDisabled(model.busy)
        }
    }

    @MainActor public struct SignOutPendingContent: View {
        @Environment(\.locale) private var locale
        private let model: SettingsHomeModel
        private let onHeightChange: (CGFloat) -> Void

        public init(model: SettingsHomeModel, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
            self.model = model
            self.onHeightChange = onHeightChange
        }

        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AuthTokens.cardGap) {
                    Text(
                        SettingsStrings.text(
                            "Sign out and lose %lld changes?", language: language, count: model.confirmationCount)
                    )
                    .font(Typography.screenCardTitle.font).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings.pending.title")
                    Text(
                        t(
                            "These haven't reached your account yet. If you sign out now, they're removed from this phone."
                        )
                    )
                    .font(Typography.screenBodyLg.font).foregroundStyle(ColorToken.mutedForeground.color)
                    VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                        ForEach(model.state.pending) { change in
                            HStack(spacing: AuthTokens.bannerGap) {
                                if let category = change.category { CategorySwatch(category, size: .small) }
                                Text(change.text(language: language)).font(Typography.screenBody.font)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.accessibilityElement(children: .combine)
                        }
                    }.padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusXl)
                        )
                        .accessibilityIdentifier("settings.pending.items")
                    VStack(spacing: AuthTokens.brandGap) {
                        Button {
                            model.stay()
                        } label: {
                            Text(t("Stay signed in")).frame(maxWidth: .infinity)
                                .frame(minHeight: PlanUITokens.actionMinHeight)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .accessibilityIdentifier("settings.pending.stay")
                        Button(role: .destructive) {
                            Task { await model.signOut(discardPending: true) }
                        } label: {
                            Text(t("Sign out and discard")).frame(maxWidth: .infinity)
                                .frame(minHeight: PlanUITokens.actionMinHeight)
                        }.buttonStyle(.borderless).foregroundStyle(ColorToken.destructive.color)
                            .accessibilityIdentifier("settings.pending.discard")
                    }.font(Typography.screenLabel.font).disabled(model.busy)
                    Text(t("Changes sync by themselves when you're online. Staying signed in keeps them."))
                        .font(Typography.screenMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }.padding(.horizontal, PlanUITokens.space5).padding(.top, PlanUITokens.space8)
                    .padding(.bottom, PlanUITokens.space8)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        onHeightChange($0)
                    }
            }.foregroundStyle(ColorToken.cardForeground.color).background(ColorToken.card.color)
                .tint(ColorToken.primary.color).accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.pending")
        }
    }
#endif

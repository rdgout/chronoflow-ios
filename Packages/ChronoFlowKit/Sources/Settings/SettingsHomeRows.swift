#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import LocalStore
    import SwiftUI

    @MainActor public struct SettingsProfileRow: View {
        private let account: AccountRecord
        private let initials: String

        public init(account: AccountRecord, initials: String) {
            self.account = account
            self.initials = initials
        }

        public var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                Text(initials).font(Typography.screenBodyLg.font).fontWeight(.semibold)
                    .frame(width: AuthTokens.touch, height: AuthTokens.touch)
                    .foregroundStyle(ColorToken.primaryForeground.color)
                    .background(ColorToken.primary.color, in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name).font(Typography.screenBodyLg.font).fontWeight(.semibold)
                    Text(account.email).font(Typography.screenBody.font).foregroundStyle(
                        ColorToken.mutedForeground.color
                    )
                    .lineLimit(1)
                }
            }.padding(.vertical, PlanUITokens.space3).frame(minHeight: PlanUITokens.space16 + PlanUITokens.space2)
                .accessibilityElement(children: .combine)
        }
    }

    @MainActor public struct SettingsSyncRow: View {
        @Environment(\.locale) private var locale
        private let copy: SettingsCopy
        private let pending: Bool
        private let offline: Bool

        public init(copy: SettingsCopy, pending: Bool, offline: Bool) {
            self.copy = copy
            self.pending = pending
            self.offline = offline
        }

        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }

        public var body: some View {
            Label(
                text,
                systemImage: pending ? "icloud.and.arrow.up" : offline ? "icloud.slash" : "checkmark.icloud"
            )
            .font(Typography.screenMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
            .monospacedDigit().accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.sync")
        }

        private var text: String {
            guard copy.key == "Synced on {{date}}", let raw = copy.values["date"],
                let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                    ?? (try? Date.ISO8601FormatStyle().parse(raw))
            else { return copy.text(language: language) }
            return SettingsStrings.text(
                copy.key, language: language,
                ["date": date.formatted(.dateTime.day().month(.abbreviated).locale(locale))])
        }
    }

    @MainActor public struct SettingsDestinationRow: View {
        @Environment(\.locale) private var locale
        private let destination: SettingsDestination
        private let credits: Int?
        private let missingAnswers: Int

        public init(destination: SettingsDestination, credits: Int?, missingAnswers: Int) {
            self.destination = destination
            self.credits = credits
            self.missingAnswers = missingAnswers
        }

        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }

        public var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                Image(systemName: destination.symbol).font(Typography.screenBodyLg.font)
                    .frame(
                        width: PlanUITokens.space8 + PlanUITokens.space1,
                        height: PlanUITokens.space8 + PlanUITokens.space1
                    )
                    .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                    Text(t(destination.title)).font(Typography.screenBodyLg.font).fontWeight(.medium)
                    if let subtitle = destination.subtitle {
                        Text(t(subtitle)).font(Typography.screenBody.font).foregroundStyle(
                            ColorToken.mutedForeground.color)
                    } else if destination == .plan, let credits {
                        Text(SettingsStrings.text("%lld credits left", language: language, count: credits))
                            .font(Typography.screenBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                            .monospacedDigit()
                    }
                    if destination == .bodyClock, missingAnswers > 0 {
                        Text(SettingsStrings.text("%lld to answer", language: language, count: missingAnswers))
                            .font(Typography.screenMeta.font).foregroundStyle(ColorToken.dawnForeground.color)
                            .padding(.horizontal, PlanUITokens.space2).padding(.vertical, PlanUITokens.space1)
                            .background(ColorToken.dawn.color, in: Capsule())
                            .accessibilityIdentifier("settings.readiness")
                    }
                }
            }.frame(minHeight: PlanUITokens.space16).accessibilityElement(children: .combine)
        }
    }

    @MainActor public struct SettingsSignOutButton: View {
        @Environment(\.locale) private var locale
        private let model: SettingsHomeModel

        public init(model: SettingsHomeModel) { self.model = model }

        public var body: some View {
            Button {
                Task { await model.signOut() }
            } label: {
                Text(
                    SettingsStrings.text(
                        "Sign out", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                )
                .font(Typography.screenLabel.font).foregroundStyle(ColorToken.foreground.color)
                .frame(maxWidth: .infinity, minHeight: PlanUITokens.actionMinHeight)
                .background(ColorToken.background.color, in: Capsule())
                .overlay { Capsule().strokeBorder(ColorToken.input.color, lineWidth: AuthTokens.borderWidth) }
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .disabled(model.busy || model.state.account == nil).accessibilityIdentifier("settings.signOut")
        }
    }
#endif

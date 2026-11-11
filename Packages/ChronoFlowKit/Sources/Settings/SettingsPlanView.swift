#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    @MainActor public struct SettingsPlanView: View {
        @Environment(\.locale) private var locale
        private let store: SettingsPagesModel
        private let offline: Bool
        private let refresh: @MainActor () async -> Void
        public init(store: SettingsPagesModel, offline: Bool, refresh: @escaping @MainActor () async -> Void) {
            self.store = store
            self.offline = offline
            self.refresh = refresh
        }
        private var state: SettingsPlanState {
            SettingsPlanState(
                credits: store.settings["planCredits"], billing: store.settings["billing"],
                loaded: store.settingsLoaded, offline: offline)
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        public var body: some View {
            SettingsPage("Plan & credits", identifier: "settings.plan.screen", spacing: PlanUITokens.space5) {
                if !state.loaded {
                    SettingsPlanLoading().accessibilityLabel(t("Loading your plan"))
                } else {
                    if state.paymentPending {
                        AuthNotice(
                            title: t("Payment processing."),
                            message: t("Your credit shows up here in a minute or two. You can leave this screen."))
                    }
                    if state.paymentFailed {
                        AuthNotice(title: t("Your last payment failed."), message: paymentFailure, tone: .warning)
                    }
                    if state.hasBalance {
                        hero
                        if !state.unlimited {
                            Text(
                                t("Credits and plans aren't sold in the app. Your balance updates here automatically.")
                            )
                            .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                            .padding(.horizontal, PlanUITokens.space1).accessibilityIdentifier("settings.plan.noLink")
                        }
                    } else {
                        SettingsStoredState(loaded: true, failed: false) { Task { await refresh() } }
                    }
                    if offline {
                        Text(t("Needs a connection. Your plans and reminders still work."))
                            .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                }
            }.refreshable { await refresh() }
        }
        private var hero: some View {
            SettingsCard(spacing: state.unlimited ? PlanUITokens.space3 : PlanUITokens.space4) {
                SettingsEyebrow(title: t("Your plan"), dawn: true)
                SettingsFlowLayout(spacing: PlanUITokens.space2, centered: true) {
                    Text(
                        state.unlimited
                            ? t("Unlimited trips")
                            : SettingsStrings.text("%lld credits left", language: language, count: state.credits ?? 0)
                    )
                    .settingsFont(Typography.screenPageTitle).monospacedDigit().accessibilityIdentifier(
                        "settings.plan.balance")
                    if state.unlimited && state.cancelled { SettingsBadge(title: t("Cancelled")) }
                }
                if state.unlimited {
                    if let raw = state.date, let date = parseDate(raw) {
                        Text(
                            SettingsStrings.text(
                                state.cancelled
                                    ? "Ends on {{date}}. After that, you can buy credits per trip."
                                    : "Renews on {{date}} · {{interval}}", language: language,
                                ["date": formattedDate(date), "interval": t(state.interval)])
                        )
                        .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                        .monospacedDigit()
                    }
                } else {
                    Text(
                        t(
                            "One credit plans one direction of a trip, so a return trip uses 2. Small time shifts are free."
                        )
                    )
                    .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                }
            }
        }
        private var paymentFailure: String {
            if let raw = state.date, let date = parseDate(raw) {
                return SettingsStrings.text(
                    "Update your payment method on the website to keep unlimited trips after {{date}}.",
                    language: language, ["date": formattedDate(date)])
            }
            return t("Update your payment method on the website to keep unlimited trips.")
        }
        private func formattedDate(_ date: Date) -> String {
            date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        }
        private func parseDate(_ raw: String) -> Date? {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                ?? (try? Date.ISO8601FormatStyle().parse(raw))
                ?? (try? Date(raw, strategy: .dateTime.year().month().day().locale(Locale(identifier: "en_US_POSIX"))))
        }
    }

    struct SettingsPlanLoading: View {
        var body: some View {
            VStack(spacing: PlanUITokens.space5) {
                SettingsCard(shadow: false, spacing: PlanUITokens.space3) {
                    skeleton(width: SettingsTokens.skeletonEyebrowWidth, height: PlanUITokens.space4)
                    skeleton(
                        width: SettingsTokens.skeletonTitleWidth, height: SettingsTokens.rowDisc,
                        radius: PlanUITokens.radiusMd)
                    skeleton(height: PlanUITokens.space4)
                    GeometryReader { proxy in
                        skeleton(
                            width: proxy.size.width * SettingsTokens.skeletonLineRatio, height: PlanUITokens.space4)
                    }.frame(height: PlanUITokens.space4)
                    skeleton(height: PlanUITokens.walkthroughDoneHeight).padding(.top, PlanUITokens.space2)
                }
                SettingsLoadingRows()
            }.accessibilityElement(children: .ignore).accessibilityIdentifier("settings.plan.loading")
        }
        private func skeleton(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = PlanUITokens.radiusFull)
            -> some View
        {
            RoundedRectangle(cornerRadius: radius).fill(ColorToken.muted.color)
                .frame(width: width, height: height).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif

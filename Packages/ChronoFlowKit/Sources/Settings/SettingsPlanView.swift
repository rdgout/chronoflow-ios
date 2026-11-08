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
            SettingsPage("Plan & credits", identifier: "settings.plan.screen") {
                if !state.loaded {
                    ProgressView(t("Loading"))
                } else {
                    if state.paymentPending {
                        Text(t("Payment processing."))
                        Text(t("Your credit shows up here in a minute or two. You can leave this screen."))
                    }
                    if state.paymentFailed {
                        Text(t("Your last payment failed."))
                        Text(
                            t(
                                state.unlimited
                                    ? "Update your payment method to keep unlimited trips."
                                    : "Update your payment method to get unlimited trips back."))
                    }
                    if state.hasBalance {
                        Section(t("Your plan")) {
                            Text(
                                state.unlimited
                                    ? t("Unlimited trips")
                                    : SettingsStrings.text(
                                        "%lld credits left", language: language, count: state.credits ?? 0)
                            )
                            .font(Typography.screenPageTitle.font).accessibilityIdentifier("settings.plan.balance")
                            if state.unlimited {
                                if state.cancelled { Text(t("Cancelled")) }
                                if let raw = state.date, let date = parseDate(raw) {
                                    Text(
                                        SettingsStrings.text(
                                            state.cancelled
                                                ? "Ends on {{date}}. After that, you can buy credits per trip."
                                                : "Renews on {{date}} · {{interval}}", language: language,
                                            [
                                                "date": date.formatted(
                                                    .dateTime.day().month(.abbreviated).year().locale(locale)),
                                                "interval": t(state.interval),
                                            ]))
                                }
                            } else {
                                Text(
                                    t(
                                        "One credit plans one direction of a trip, so a return trip uses 2. Small time shifts are free."
                                    ))
                            }
                        }
                        Text(t("Credits and plans aren't sold in the app. Your balance updates here automatically."))
                            .foregroundStyle(ColorToken.mutedForeground.color).accessibilityIdentifier(
                                "settings.plan.noLink")
                    }
                    if offline || !state.hasBalance {
                        Text(t("Needs a connection."))
                        Button(t("Try again")) { Task { await refresh() } }.accessibilityIdentifier(
                            "settings.plan.retry")
                    }
                }
            }.refreshable { await refresh() }
        }
        private func parseDate(_ raw: String) -> Date? {
            (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                ?? (try? Date.ISO8601FormatStyle().parse(raw))
                ?? (try? Date(raw, strategy: .dateTime.year().month().day().locale(Locale(identifier: "en_US_POSIX"))))
        }
    }
#endif

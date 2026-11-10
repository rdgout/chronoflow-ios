#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    struct SettingsPasswordPrompt: View {
        @Environment(\.locale) private var locale
        let detail: String
        let button: String
        let destructive: Bool
        @Binding var password: String
        let busy: Bool
        let retryAt: Date?
        let error: String?
        var message: String? = nil
        let email: String
        let identifier: String
        var fieldIdentifier: String? = nil
        var submitIdentifier: String? = nil
        var errorIdentifier: String? = nil
        let cancel: () -> Void
        let submit: () async -> Void
        let reset: () async -> Void
        @State private var showingReset = false
        @FocusState private var passwordFocused: Bool
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        var body: some View {
            SettingsCompactSheet(title: t("Confirm it's you"), cancel: cancel, busy: busy) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(ceil(retryAt?.timeIntervalSince(context.date) ?? 0)))
                    let alert =
                        remaining > 0
                        ? SettingsStrings.lockout(seconds: remaining, language: language)
                        : error
                    VStack(alignment: .leading, spacing: PlanUITokens.radiusLg) {
                        Text(t(detail)).settingsFont(Typography.settingsPromptBody).foregroundStyle(
                            ColorToken.mutedForeground.color)
                        VStack(alignment: .leading, spacing: SettingsTokens.pillGap) {
                            SecureField(t("Password"), text: $password).textContentType(.password).focused(
                                $passwordFocused
                            )
                            .padding(.horizontal, PlanUITokens.space4)
                            .frame(minHeight: SettingsTokens.promptFieldHeight)
                            .background(
                                ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusMd)
                            )
                            .overlay {
                                if alert != nil {
                                    RoundedRectangle(cornerRadius: PlanUITokens.radiusMd)
                                        .strokeBorder(
                                            ColorToken.destructive.color, lineWidth: SettingsTokens.selectionWidth)
                                }
                            }
                            .disabled(busy || remaining > 0)
                            .opacity(busy || remaining > 0 ? SettingsTokens.dimmedFieldOpacity : 1)
                            .accessibilityIdentifier(fieldIdentifier ?? identifier + ".password")
                            if let alert {
                                HStack(alignment: .top, spacing: SettingsTokens.pillGap) {
                                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                                    Text(alert).accessibilityIdentifier(errorIdentifier ?? identifier + ".error")
                                }.settingsFont(Typography.screenBody).foregroundStyle(ColorToken.destructive.color)
                            }
                            Button {
                                showingReset = true
                            } label: {
                                Text(t("Forgot password?")).underline().settingsFont(Typography.screenBody).fontWeight(
                                    .medium
                                )
                                .frame(minHeight: PlanUITokens.walkthroughDoneHeight)
                            }.buttonStyle(.plain).disabled(busy || remaining > 0)
                                .accessibilityIdentifier(identifier + ".forgot")
                        }
                        if let message, remaining == 0 {
                            Text(t(message)).settingsFont(Typography.screenBody).foregroundStyle(
                                ColorToken.mutedForeground.color
                            )
                            .accessibilityIdentifier(identifier + ".feedback")
                        }
                        AuthButton(
                            t(busy ? "Checking…" : button), kind: destructive ? .destructive : .primary, busy: busy,
                            minimumHeight: SettingsTokens.promptButtonHeight, labelStyle: Typography.settingsStrong,
                            disabledOpacity: SettingsTokens.disabledOpacity
                        ) {
                            passwordFocused = false
                            Task { await submit() }
                        }
                        .disabled(busy || remaining > 0 || password.isEmpty)
                        .accessibilityIdentifier(submitIdentifier ?? identifier + ".submit")
                    }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
            }
            .alert(t("Reset your password?"), isPresented: $showingReset) {
                Button(t("Cancel"), role: .cancel) {}
                Button(t("Send link")) { Task { await reset() } }
            } message: {
                Text(
                    SettingsStrings.text(
                        "We'll email a reset link to {{email}}. You stay signed in on this phone.", language: language,
                        ["email": email]))
            }
        }
    }
#endif

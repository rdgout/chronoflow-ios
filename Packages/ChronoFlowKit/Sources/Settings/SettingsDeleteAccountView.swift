#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    @MainActor struct SettingsDeleteAccountView: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        @State private var model: SettingsDeleteModel
        @State private var resetModel: SettingsSecurityModel
        let email: String
        init(
            delete: @escaping @MainActor (String) async throws -> Void, email: String,
            security: @escaping @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult
        ) {
            self.email = email
            _model = State(initialValue: SettingsDeleteModel(delete: delete))
            _resetModel = State(initialValue: SettingsSecurityModel(perform: security))
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        var body: some View {
            ZStack {
                if model.stage == .confirmation {
                    SettingsCompactSheet {
                        VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                            Text(t("Delete your account?")).settingsFont(Typography.screenCardTitle)
                            Text(
                                t(
                                    "Your trips, plans, body-clock answers and any credits left are deleted for good, here and on the web. This can't be undone."
                                )
                            )
                            .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
                        }
                        VStack(spacing: PlanUITokens.space2) {
                            AuthButton(
                                t("Delete my account"), kind: .destructive, minimumHeight: PlanUITokens.actionMinHeight
                            ) { model.confirmDeletion() }
                            .accessibilityIdentifier("settings.delete.confirm")
                            SettingsLockHint(title: t("You'll be asked for your password next."))
                            AuthButton(
                                t("Keep my account"), kind: .ghost, minimumHeight: PlanUITokens.walkthroughDoneHeight
                            ) { dismiss() }
                            .accessibilityIdentifier("settings.delete.keep")
                        }
                    }
                } else {
                    SettingsPasswordPrompt(
                        detail: "Enter your password to delete your account. This can't be undone.",
                        button: "Delete account", destructive: true,
                        password: $model.password, busy: model.busy || resetModel.busy, retryAt: retryAt,
                        error: model.errorKey.map(t), message: resetModel.message,
                        email: email, identifier: "settings.delete.prompt", fieldIdentifier: "settings.delete.password",
                        submitIdentifier: "settings.delete.submit", errorIdentifier: "settings.delete.error",
                        cancel: { dismiss() }, submit: { await model.submit() },
                        reset: { await resetModel.sendReset(email: email) })
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("settings.delete.screen")
                .onDisappear {
                    model.stop()
                    resetModel.clearSecrets()
                }
        }
        private var retryAt: Date? { [model.retryAt, resetModel.retryAt].compactMap { $0 }.max() }
    }
#endif

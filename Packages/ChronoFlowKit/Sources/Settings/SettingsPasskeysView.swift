#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    @MainActor struct SettingsPasskeysView: View {
        @Environment(\.locale) private var locale
        @Environment(\.scenePhase) private var scenePhase
        @State private var model: SettingsSecurityModel
        let store: SettingsPagesModel
        init(store: SettingsPagesModel) {
            self.store = store
            _model = State(
                initialValue: SettingsSecurityModel(
                    perform: store.performSecurity, registration: store.passkeyRegistration,
                    deviceName: store.deviceName))
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        private func promptDetail(_ action: SettingsSecurityPrompt) -> String {
            SettingsStrings.text(action.detail, language: language, ["name": model.removal?.name ?? ""])
        }
        var body: some View {
            SettingsPage("Passkeys", identifier: "settings.passkeys.screen") {
                Text(t("Sign in with Face ID, a fingerprint or your screen lock instead of your password."))
                    .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
                content
                if SettingsSecurityModel.passkeyRegistrationSupported {
                    AuthButton(t("Add a passkey"), minimumHeight: PlanUITokens.actionMinHeight) {
                        model.showPrompt(.addPasskey)
                    }
                    .disabled(!model.canRegisterPasskey || model.busy || model.offline || model.locked)
                    .accessibilityHint(model.offline ? t("Needs a connection.") : "")
                    .accessibilityIdentifier("settings.passkeys.add")
                }
                if model.offline, SettingsSecurityModel.passkeyRegistrationSupported {
                    Text(t("Needs a connection.")).settingsFont(Typography.screenBody)
                        .foregroundStyle(ColorToken.mutedForeground.color)
                        .accessibilityIdentifier("settings.passkeys.offline")
                }
                SettingsSecurityLock(model: model)
            }.safeAreaInset(edge: .bottom, spacing: 0) {
                if model.prompt == nil { SettingsSecurityFeedback(model: model) }
            }.sheet(item: $model.prompt, onDismiss: { model.promptPassword = "" }) { action in
                SettingsPasswordPrompt(
                    detail: promptDetail(action), button: action.button, destructive: action == .removePasskey,
                    password: $model.promptPassword, busy: model.busy, retryAt: model.retryAt,
                    error: model.errorText("current_password", language: language), message: model.message,
                    email: store.account?.email ?? "", identifier: "settings.passkeys.prompt",
                    cancel: model.cancelPrompt, submit: { await model.submitPrompt() },
                    reset: { await model.sendReset(email: store.account?.email ?? "") }
                )
                .task(id: model.retryAt) { await refreshLock(model) }
            }
            .task { await model.loadPasskeys() }
            .refreshable { await model.loadPasskeys() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, model.offline { Task { await model.loadPasskeys() } }
            }
            .onDisappear { model.clearSecrets() }.task(id: model.retryAt) { await refreshLock(model) }
        }
        @ViewBuilder private var content: some View {
            if let passkeys = model.passkeys {
                if passkeys.isEmpty { empty } else { list(passkeys) }
            } else if model.passkeysUnavailable {
                if !model.offline {
                    VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                        SettingsError(title: t("Something went wrong"))
                        AuthButton(
                            t("Try again"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight
                        ) { Task { await model.loadPasskeys() } }
                        .accessibilityIdentifier("settings.passkeys.retry")
                    }
                }
            } else {
                SettingsLoadingRows().accessibilityLabel(t("Loading"))
            }
        }
        private func list(_ passkeys: [ApiPasskey]) -> some View {
            SettingsCard(rows: true) {
                ForEach(Array(passkeys.enumerated()), id: \.element.id) { index, passkey in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: PlanUITokens.space3) {
                        Image(systemName: "key").settingsFont(Typography.screenBodyLg)
                            .frame(width: SettingsTokens.rowDisc, height: SettingsTokens.rowDisc)
                            .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(passkey.name).settingsFont(Typography.settingsRow)
                                .foregroundStyle(ColorToken.cardForeground.color)
                            if let meta = SettingsPasskeyText.meta(
                                passkey, language: language, locale: locale, now: Date())
                            {
                                Text(meta).settingsFont(Typography.screenBody).monospacedDigit()
                                    .foregroundStyle(ColorToken.mutedForeground.color)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            model.showPrompt(.removePasskey, removing: passkey)
                        } label: {
                            Image(systemName: "trash").settingsFont(Typography.screenBodyLg)
                                .frame(minWidth: AuthTokens.touch, minHeight: AuthTokens.touch)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(ColorToken.foreground.color)
                            .disabled(model.busy || model.offline)
                            .accessibilityLabel(
                                SettingsStrings.text(
                                    "Remove passkey {{name}}", language: language, ["name": passkey.name])
                            )
                            .accessibilityHint(model.offline ? t("Needs a connection.") : "")
                            .accessibilityIdentifier("settings.passkeys.remove")
                    }
                    .padding(.leading, PlanUITokens.space4).padding(.trailing, PlanUITokens.space2)
                    .padding(.vertical, PlanUITokens.space2).frame(minHeight: SettingsTokens.rowHeight)
                    .accessibilityElement(children: .contain)
                }
            }.accessibilityElement(children: .contain).accessibilityLabel(t("Your passkeys"))
                .accessibilityIdentifier("settings.passkeys.list")
        }
        private var empty: some View {
            VStack(spacing: PlanUITokens.space3) {
                Image(systemName: "key").settingsFont(Typography.screenBodyLg)
                    .frame(width: PlanUITokens.actionMinHeight, height: PlanUITokens.actionMinHeight)
                    .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                Text(t("No passkeys yet")).settingsFont(Typography.settingsStrong)
                    .foregroundStyle(ColorToken.foreground.color)
                Text(t("Add one on this phone and you can sign in without typing a password."))
                    .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, PlanUITokens.space8).padding(.horizontal, PlanUITokens.space5)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                    .strokeBorder(
                        ColorToken.border.color,
                        style: StrokeStyle(lineWidth: SettingsTokens.selectionWidth, dash: [PlanUITokens.space2]))
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("settings.passkeys.empty")
        }
    }
#endif

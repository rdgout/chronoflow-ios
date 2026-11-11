#if canImport(UIKit)
    import AppCore
    import CoreImage.CIFilterBuiltins
    import DesignSystem
    import SwiftUI
    import UIKit

    @MainActor public struct SettingsSecurityView: View {
        @Environment(\.locale) private var locale
        private let store: SettingsPagesModel
        public init(store: SettingsPagesModel) { self.store = store }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        public var body: some View {
            SettingsPage("Security", identifier: "settings.security.screen") {
                if let security = store.settings["security"] {
                    SettingsCard(rows: true) {
                        NavigationLink {
                            SettingsPasswordView(perform: store.performSecurity)
                        } label: {
                            SettingsRow(title: t("Password"), subtitle: t("Change your password"), symbol: "lock")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.security.password")
                        SettingsDivider()
                        NavigationLink {
                            SettingsTwoFactorView(store: store)
                        } label: {
                            SettingsRow(
                                title: t("Two-factor authentication"),
                                subtitle: t("A code from an app when you sign in"), symbol: "iphone",
                                badge: t(security["twoFactorEnabled"] == .bool(true) ? "On" : "Off"),
                                badgeOn: security["twoFactorEnabled"] == .bool(true))
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.security.twoFactor")
                    }
                } else {
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure) {
                        Task { await store.retry() }
                    }
                }
            }
        }
    }

    @MainActor private struct SettingsPasswordView: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsSecurityModel
        @FocusState private var focus: String?
        init(perform: @escaping @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult) {
            _model = State(initialValue: SettingsSecurityModel(perform: perform))
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        var body: some View {
            SettingsPage("Password", identifier: "settings.password.screen") {
                if !model.errors.isEmpty {
                    AuthNotice(
                        title: t("Check the highlighted field."), message: t("Your new password isn't saved yet."),
                        tone: .warning)
                }
                SettingsCard {
                    AuthField(
                        t("Current password"), text: $model.currentPassword, secure: true,
                        error: model.errorText("current_password", language: language),
                        identifier: "settings.password.current", contentType: .password, focus: $focus
                    ) { focus = "settings.password.new" }
                    AuthField(
                        t("New password"), text: $model.newPassword, secure: true,
                        error: model.errorText("password", language: language), identifier: "settings.password.new",
                        contentType: .newPassword, focus: $focus
                    ) { focus = "settings.password.confirmation" }
                    AuthField(
                        t("Confirm new password"), text: $model.confirmation, secure: true,
                        error: model.errorText("password_confirmation", language: language),
                        identifier: "settings.password.confirmation", contentType: .newPassword, submitLabel: .done,
                        focus: $focus
                    ) { focus = nil }
                }.disabled(model.busy)
                AuthButton(t("Change password"), busy: model.busy, minimumHeight: PlanUITokens.actionMinHeight) {
                    focus = nil
                    Task { await model.changePassword() }
                }.disabled(model.busy || model.locked).accessibilityIdentifier("settings.password.save")
                SettingsSecurityLock(model: model)
            }.safeAreaInset(edge: .bottom, spacing: 0) { SettingsSecurityFeedback(model: model) }
                .onDisappear { model.clearSecrets() }.task(id: model.retryAt) { await refreshLock(model) }
        }
    }

    @MainActor private struct SettingsTwoFactorView: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsSecurityModel
        @FocusState private var focus: String?
        let store: SettingsPagesModel
        init(store: SettingsPagesModel) {
            self.store = store
            _model = State(initialValue: SettingsSecurityModel(perform: store.performSecurity))
        }
        #if DEBUG
            init(store: SettingsPagesModel, model: SettingsSecurityModel) {
                self.store = store
                _model = State(initialValue: model)
            }
        #endif
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        private var enabled: Bool {
            store.settings["security"]?["twoFactorEnabled"] == .bool(true) || !model.codes.isEmpty
        }
        var body: some View {
            SettingsPage(
                "Two-factor authentication", identifier: "settings.twoFactor.screen", spacing: PlanUITokens.space5
            ) {
                if let setup = model.setup { setupContent(setup) } else if enabled { manage } else { introduction }
                SettingsSecurityLock(model: model)
            }.safeAreaInset(edge: .bottom, spacing: 0) {
                if model.prompt == nil { SettingsSecurityFeedback(model: model) }
            }.sheet(item: $model.prompt, onDismiss: { model.promptPassword = "" }) { action in
                SettingsPasswordPrompt(
                    detail: action.detail, button: action.button, destructive: action == .disable,
                    password: $model.promptPassword, busy: model.busy, retryAt: model.retryAt,
                    error: model.errorText("current_password", language: language), message: model.message,
                    email: store.account?.email ?? "", identifier: "settings.security.prompt",
                    cancel: model.cancelPrompt, submit: { await model.submitPrompt() },
                    reset: { await model.sendReset(email: store.account?.email ?? "") }
                )
                .task(id: model.retryAt) { await refreshLock(model) }
            }.onDisappear { model.clearSecrets() }.task(id: model.retryAt) { await refreshLock(model) }
        }
        private var introduction: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space5) {
                SettingsBadge(title: t("Off"))
                SettingsCard(spacing: PlanUITokens.radiusLg) {
                    Text(
                        t(
                            "Ask for a code from an authenticator app each time you sign in with your password, so a stolen password isn't enough."
                        ))
                    VStack(alignment: .leading, spacing: SettingsTokens.pillGap) {
                        bullet("You need an authenticator app, like the one built into Passwords on iPhone.")
                        bullet("You get recovery codes for when you lose your phone.")
                        bullet("Signing in with a passkey doesn't ask for a code.")
                    }
                    AuthButton(t("Turn on two-factor"), minimumHeight: PlanUITokens.actionMinHeight) {
                        model.showPrompt(.enable)
                    }
                    .accessibilityIdentifier("settings.twoFactor.enable")
                    SettingsLockHint(title: t("You'll be asked for your password first."))
                }
            }
        }
        private func bullet(_ key: String) -> some View {
            HStack(alignment: .top, spacing: SettingsTokens.pillGap) {
                Text(verbatim: "•").accessibilityHidden(true)
                Text(t(key))
            }.settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
        }
        @ViewBuilder private func setupContent(_ setup: ApiTwoFactorSetup) -> some View {
            Text(t("When it's on, you sign in with your password and a code from an authenticator app."))
                .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
            SettingsCard {
                step(1, "1 · Scan this code with your authenticator app")
                SettingsAuthenticatorQR(value: setup.otpauthUrl).frame(maxWidth: .infinity)
                Text(t("Using this phone? Copy the setup key into the app instead."))
                    .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                HStack(spacing: PlanUITokens.space2) {
                    SettingsCodeText(value: setup.secretKey).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(
                            "settings.twoFactor.secret")
                    AuthButton(t("Copy"), kind: .outline, minimumHeight: PlanUITokens.walkthroughDoneHeight) {
                        copy(setup.secretKey)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }.padding(SettingsTokens.pillGap).padding(.leading, PlanUITokens.space2)
                    .background(ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusLg))
            }
            SettingsCard {
                step(2, "2 · Enter the 6-digit code it shows")
                AuthField(
                    t("6-digit code"), text: $model.code, error: model.errors["code"].map(t), placeholder: t("123456"),
                    identifier: "settings.twoFactor.code", contentType: .oneTimeCode, keyboard: .numberPad,
                    submitLabel: .done, focus: $focus
                ) { focus = nil }
            }
            if model.twoFactorActivationFailed {
                AuthBanner(
                    title: t("Couldn't turn on two-factor."),
                    message: t("Nothing changed on your account. Try again in a moment.")
                ).accessibilityIdentifier("settings.twoFactor.failure")
            }
            AuthButton(
                t(model.twoFactorActivationFailed ? "Try again" : "Turn on two-factor"), busy: model.busy,
                minimumHeight: PlanUITokens.actionMinHeight
            ) {
                focus = nil
                Task { await model.confirm() }
            }.disabled(model.busy || model.locked).accessibilityIdentifier("settings.twoFactor.confirm")
        }
        private func step(_ number: Int, _ key: String) -> some View {
            var text = AttributedString(t(key))
            text.font = Typography.screenLabel.font
            if let range = text.range(of: String(number)) { text[range].foregroundColor = ColorToken.dawnText.color }
            return Text(text)
        }
        @ViewBuilder private var manage: some View {
            HStack(spacing: PlanUITokens.space2) {
                SettingsBadge(title: t("On"), dawn: true)
                if let raw = store.settings["security"]?["twoFactorConfirmedAt"]?.string,
                    let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                        ?? (try? Date.ISO8601FormatStyle().parse(raw))
                {
                    Text(
                        SettingsStrings.text(
                            "Since {{date}}", language: language,
                            ["date": date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))])
                    )
                    .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                    .monospacedDigit()
                }
            }
            if model.codes.isEmpty {
                VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                    SettingsEyebrow(title: t("Recovery codes"))
                    SettingsCard(rows: true) {
                        promptButton(.reveal, "Show recovery codes", "Each code works once and is then replaced")
                    }
                }
            } else {
                SettingsCard {
                    VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                        Text(t("Recovery codes")).settingsFont(Typography.screenSectionTitle)
                        Text(
                            t(
                                "If you lose your phone, sign in with one of these. Each code works once and is then replaced. Keep them somewhere safe."
                            )
                        )
                        .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PlanUITokens.space2) {
                        ForEach(model.codes, id: \.self) { code in
                            SettingsCodeText(value: code).textSelection(.enabled)
                                .accessibilityIdentifier("settings.twoFactor.recoveryCode")
                        }
                    }.padding(PlanUITokens.space3).background(
                        ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusLg))
                    HStack(spacing: PlanUITokens.space2) {
                        AuthButton(t("Copy"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight) {
                            copy(model.codes.joined(separator: "\n"))
                        }
                        ShareLink(
                            item: SettingsRecoveryDocument(
                                text: model.codes.joined(separator: "\n"), name: t("Recovery codes") + ".txt"),
                            preview: SharePreview(t("Recovery codes"))
                        ) {
                            Text(t("Download")).settingsFont(Typography.screenLabel).foregroundStyle(
                                ColorToken.foreground.color
                            )
                            .frame(maxWidth: .infinity, minHeight: PlanUITokens.actionMinHeight)
                            .background(ColorToken.background.color, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(ColorToken.input.color, lineWidth: AuthTokens.borderWidth)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            SettingsCard(rows: true) {
                promptButton(.regenerate, "Make new codes", "Your current codes stop working")
                SettingsDivider()
                promptButton(.disable, "Turn off two-factor", "Sign in with only your password or passkey")
            }
            SettingsLockHint(title: t("Each of these asks for your password first."))
        }
        private func promptButton(_ action: SettingsSecurityPrompt, _ title: String, _ subtitle: String) -> some View {
            Button {
                model.showPrompt(action)
            } label: {
                SettingsRow(title: t(title), subtitle: t(subtitle), destructive: action == .disable, lock: true)
            }.buttonStyle(.plain).accessibilityIdentifier("settings.twoFactor." + action.rawValue)
        }
        private func copy(_ value: String) {
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: value]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        }
    }

    private struct SettingsSecurityFeedback: View {
        @Environment(\.locale) private var locale
        let model: SettingsSecurityModel
        var body: some View {
            if let key = model.message, model.retryAt == nil, !model.twoFactorActivationFailed {
                SettingsToast(
                    title: SettingsStrings.text(
                        key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en),
                    identifier: "settings.security.feedback",
                    success: [
                        "Password updated", "Two-factor is on. Save your recovery codes now.", "Check your inbox.",
                    ].contains(key))
            }
        }
    }
    private struct SettingsSecurityLock: View {
        @Environment(\.locale) private var locale
        let model: SettingsSecurityModel
        var body: some View {
            if model.retryAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    SettingsError(
                        title: SettingsStrings.lockout(
                            seconds: model.remaining(at: context.date),
                            language: locale.language.languageCode?.identifier == "nl" ? .nl : .en))
                }
            }
        }
    }
    private struct SettingsAuthenticatorQR: View {
        @Environment(\.locale) private var locale
        let value: String
        @State private var image: UIImage?
        var body: some View {
            ZStack {
                ColorToken.settingsQrBackground.color
                if let image {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(PlanUITokens.space2)
                }
            }.frame(width: SettingsTokens.qrSize, height: SettingsTokens.qrSize)
                .clipShape(RoundedRectangle(cornerRadius: PlanUITokens.radiusLg))
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radiusLg).strokeBorder(
                        ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
                .accessibilityLabel(
                    SettingsStrings.text(
                        "QR code for your authenticator app",
                        language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                )
                .task(id: value) {
                    let filter = CIFilter.qrCodeGenerator()
                    filter.message = Data(value.utf8)
                    guard let output = filter.outputImage,
                        let raster = CIContext().createCGImage(output, from: output.extent)
                    else { return }
                    image = UIImage(cgImage: raster)
                }
        }
    }
    @MainActor private func refreshLock(_ model: SettingsSecurityModel) async {
        while model.locked, !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            model.refreshLock()
        }
    }
    #if DEBUG
        @MainActor public struct SettingsSecurityUITestPage: View {
            let store: SettingsPagesModel
            let route: String
            let setupPassword: String
            @State private var model: SettingsSecurityModel
            public init(store: SettingsPagesModel, route: String, setupPassword: String) {
                self.store = store
                self.route = route
                self.setupPassword = setupPassword
                _model = State(initialValue: SettingsSecurityModel(perform: store.performSecurity))
            }
            public var body: some View {
                if route == "password" {
                    SettingsPasswordView(perform: store.performSecurity)
                } else {
                    SettingsTwoFactorView(store: store, model: model)
                        .task {
                            if route == "twoFactorSetup" {
                                model.showPrompt(.enable)
                                model.promptPassword = setupPassword
                                await model.submitPrompt()
                            }
                        }
                }
            }
        }
    #endif
#endif

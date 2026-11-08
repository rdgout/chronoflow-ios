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
                    NavigationLink {
                        SettingsPasswordView(perform: store.performSecurity)
                    } label: {
                        Label(t("Change your password"), systemImage: "lock")
                    }.accessibilityIdentifier("settings.security.password")
                    NavigationLink {
                        SettingsTwoFactorView(store: store)
                    } label: {
                        LabeledContent(
                            t("Two-factor authentication"),
                            value: t(security["twoFactorEnabled"] == .bool(true) ? "On" : "Off"))
                    }.accessibilityIdentifier("settings.security.twoFactor")
                } else {
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure)
                }
            }
        }
    }

    @MainActor private struct SettingsPasswordView: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsSecurityModel
        init(perform: @escaping @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult) {
            _model = State(initialValue: SettingsSecurityModel(perform: perform))
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            SettingsPage("Password", identifier: "settings.password.screen") {
                Section {
                    SecureField(t("Current password"), text: $model.currentPassword).textContentType(.password)
                        .accessibilityIdentifier("settings.password.current")
                    fieldError("current_password")
                    SecureField(t("New password"), text: $model.newPassword).textContentType(.newPassword)
                        .accessibilityIdentifier("settings.password.new")
                    fieldError("password")
                    SecureField(t("Confirm new password"), text: $model.confirmation).textContentType(.newPassword)
                        .accessibilityIdentifier("settings.password.confirmation")
                    fieldError("password_confirmation")
                }.disabled(model.busy)
                Button(t("Change password")) { Task { await model.changePassword() } }
                    .disabled(model.busy || model.locked).accessibilityIdentifier("settings.password.save")
                SettingsSecurityFeedback(model: model)
            }.onDisappear { model.clearSecrets() }
                .task(id: model.retryAt) { await refreshLock(model) }
        }
        @ViewBuilder private func fieldError(_ key: String) -> some View {
            if let text = model.errorText(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en) {
                Text(text).foregroundStyle(ColorToken.destructive.color)
            }
        }
    }

    @MainActor private struct SettingsTwoFactorView: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsSecurityModel
        let store: SettingsPagesModel
        init(store: SettingsPagesModel) {
            self.store = store
            _model = State(initialValue: SettingsSecurityModel(perform: store.performSecurity))
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        private var enabled: Bool {
            store.settings["security"]?["twoFactorEnabled"] == .bool(true) || !model.codes.isEmpty
        }
        var body: some View {
            SettingsPage("Two-factor authentication", identifier: "settings.twoFactor.screen") {
                if let setup = model.setup {
                    setupContent(setup)
                } else if enabled {
                    manage
                } else {
                    introduction
                }
                SettingsSecurityFeedback(model: model)
            }.sheet(item: $model.prompt, onDismiss: { model.promptPassword = "" }) { action in
                SettingsSecurityPasswordPrompt(model: model, action: action, email: store.account?.email ?? "")
            }.onDisappear { model.clearSecrets() }
                .task(id: model.retryAt) { await refreshLock(model) }
        }
        private var introduction: some View {
            Section {
                Text(t("Off"))
                Text(
                    t(
                        "Ask for a code from an authenticator app each time you sign in with your password, so a stolen password isn't enough."
                    ))
                Text(t("You need an authenticator app, like the one built into Passwords on iPhone."))
                Text(t("You get recovery codes for when you lose your phone."))
                Text(t("Signing in with a passkey doesn't ask for a code."))
                Button(t("Turn on two-factor")) { model.showPrompt(.enable) }
                    .accessibilityIdentifier("settings.twoFactor.enable")
                Text(t("You'll be asked for your password first."))
            }
        }
        @ViewBuilder private func setupContent(_ setup: ApiTwoFactorSetup) -> some View {
            Section(t("1 · Scan this code with your authenticator app")) {
                SettingsAuthenticatorQR(value: setup.otpauthUrl)
                Text(t("Using this phone? Copy the setup key into the app instead."))
                Text(setup.secretKey).font(Typography.screenBody.font).monospaced().textSelection(.enabled)
                    .accessibilityIdentifier("settings.twoFactor.secret")
                Button(t("Copy")) { copy(setup.secretKey) }
            }
            Section(t("2 · Enter the 6-digit code it shows")) {
                TextField(t("6-digit code"), text: $model.code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .accessibilityIdentifier("settings.twoFactor.code")
                if let error = model.errors["code"] { Text(t(error)).foregroundStyle(ColorToken.destructive.color) }
                Button(t("Turn on two-factor")) { Task { await model.confirm() } }
                    .disabled(model.busy || model.locked).accessibilityIdentifier("settings.twoFactor.confirm")
            }
        }
        @ViewBuilder private var manage: some View {
            Section {
                Text(t("On"))
                if let raw = store.settings["security"]?["twoFactorConfirmedAt"]?.string,
                    let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                        ?? (try? Date.ISO8601FormatStyle().parse(raw))
                {
                    Text(
                        SettingsStrings.text(
                            "Since {{date}}", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                            ["date": date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))])
                    ).monospacedDigit()
                }
            }
            Section(t("Recovery codes")) {
                if model.codes.isEmpty {
                    promptButton(.reveal, "Show recovery codes")
                    Text(t("Each code works once and is then replaced"))
                } else {
                    Text(
                        t(
                            "If you lose your phone, sign in with one of these. Each code works once and is then replaced. Keep them somewhere safe."
                        ))
                    ForEach(model.codes, id: \.self) {
                        Text($0).font(Typography.screenBody.font).monospaced().textSelection(.enabled)
                            .accessibilityIdentifier("settings.twoFactor.recoveryCode")
                    }
                    Button(t("Copy")) { copy(model.codes.joined(separator: "\n")) }
                    ShareLink(item: model.codes.joined(separator: "\n")) { Text(t("Download")) }
                }
            }
            Section {
                promptButton(.regenerate, "Make new codes")
                Text(t("Your current codes stop working"))
                Button(role: .destructive) {
                    model.showPrompt(.disable)
                } label: {
                    Label(t("Turn off two-factor"), systemImage: "lock")
                }.accessibilityIdentifier("settings.twoFactor.disable")
                Text(t("Sign in with only your password or passkey"))
                Text(t("Each of these asks for your password first."))
            }
        }
        private func promptButton(_ action: SettingsSecurityPrompt, _ title: String) -> some View {
            Button {
                model.showPrompt(action)
            } label: {
                Label(t(title), systemImage: "lock")
            }
            .accessibilityIdentifier("settings.twoFactor.\(action.rawValue)")
        }
        private func copy(_ value: String) {
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: value]],
                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        }
    }

    @MainActor private struct SettingsSecurityPasswordPrompt: View {
        @Environment(\.locale) private var locale
        @Bindable var model: SettingsSecurityModel
        let action: SettingsSecurityPrompt
        let email: String
        @State private var showingReset = false
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            NavigationStack {
                SettingsPage("Confirm it's you", identifier: "settings.security.prompt") {
                    Text(t(action.detail))
                    SecureField(t("Password"), text: $model.promptPassword).textContentType(.password)
                        .disabled(model.busy || model.locked).accessibilityIdentifier(
                            "settings.security.prompt.password")
                    if let error = model.errors["current_password"] {
                        Text(t(error)).foregroundStyle(ColorToken.destructive.color)
                    }
                    Button(t("Forgot password?")) { showingReset = true }.disabled(model.busy)
                    SettingsSecurityFeedback(model: model)
                    Button(t(model.busy ? "Checking…" : action.button), role: action == .disable ? .destructive : nil) {
                        Task { await model.submitPrompt() }
                    }.disabled(model.busy || model.locked || model.promptPassword.isEmpty)
                        .accessibilityIdentifier("settings.security.prompt.submit")
                }.toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("Cancel")) { model.cancelPrompt() }.disabled(model.busy)
                    }
                }
            }.alert(t("Reset your password?"), isPresented: $showingReset) {
                Button(t("Cancel"), role: .cancel) {}
                Button(t("Send link")) { Task { await model.sendReset(email: email) } }
            } message: {
                Text(
                    SettingsStrings.text(
                        "We'll send a link to {{email}}. You stay signed in on this phone.",
                        language: locale.language.languageCode?.identifier == "nl" ? .nl : .en, ["email": email]))
            }.interactiveDismissDisabled(model.busy).task(id: model.retryAt) { await refreshLock(model) }
        }
    }

    @MainActor private struct SettingsSecurityFeedback: View {
        @Environment(\.locale) private var locale
        let model: SettingsSecurityModel
        var body: some View {
            if let key = model.message {
                Text(SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en))
                    .accessibilityIdentifier("settings.security.feedback")
            }
            if model.retryAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(
                        SettingsStrings.text(
                            "Try again in {{seconds}} seconds.",
                            language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                            ["seconds": String(model.remaining(at: context.date))]))
                }
            }
        }
    }

    @MainActor private struct SettingsAuthenticatorQR: View {
        @Environment(\.locale) private var locale
        let value: String
        @State private var image: UIImage?
        var body: some View {
            ZStack {
                ColorToken.card.color
                if let image { Image(uiImage: image).interpolation(.none).resizable().scaledToFit() }
            }.aspectRatio(1, contentMode: .fit).accessibilityLabel(
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
#endif

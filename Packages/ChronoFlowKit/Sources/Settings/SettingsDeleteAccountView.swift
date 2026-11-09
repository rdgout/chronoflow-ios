#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    @MainActor struct SettingsDeleteAccountView: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        @State private var model: SettingsDeleteModel
        init(delete: @escaping @MainActor (String) async throws -> Void) {
            _model = State(initialValue: SettingsDeleteModel(delete: delete))
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        var body: some View {
            NavigationStack {
                SettingsPage(
                    model.stage == .confirmation ? "Delete your account?" : "Confirm it's you",
                    identifier: "settings.delete.screen"
                ) {
                    if model.stage == .confirmation {
                        Text(
                            t(
                                "Your trips, plans, body-clock answers and any credits left are deleted for good, here and on the web. This can't be undone."
                            ))
                        Button(t("Delete my account"), role: .destructive) { model.confirmDeletion() }
                            .accessibilityIdentifier("settings.delete.confirm")
                        Text(t("You'll be asked for your password next."))
                        Button(t("Keep my account")) { dismiss() }.accessibilityIdentifier("settings.delete.keep")
                    } else {
                        Text(t("Enter your password to delete your account. This can't be undone."))
                        SecureField(t("Password"), text: $model.password).textContentType(.password)
                            .disabled(model.busy).accessibilityIdentifier("settings.delete.password")
                        if let key = model.errorKey {
                            Text(t(key)).foregroundStyle(ColorToken.destructive.color)
                                .accessibilityIdentifier("settings.delete.error")
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(ceil(model.retryAt?.timeIntervalSince(context.date) ?? 0)))
                            if remaining > 0 {
                                Text(
                                    SettingsStrings.text(
                                        "Try again in {{seconds}} seconds.", language: language,
                                        ["seconds": String(remaining)]))
                            }
                            Button(t("Delete account"), role: .destructive) { Task { await model.submit() } }
                                .disabled(model.busy || remaining > 0 || model.password.isEmpty)
                                .accessibilityIdentifier("settings.delete.submit")
                        }
                    }
                }.toolbar {
                    if model.stage != .confirmation {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("Cancel")) { dismiss() }.disabled(model.busy)
                        }
                    }
                }
            }.interactiveDismissDisabled(model.busy).onDisappear { model.stop() }
        }
    }
#endif

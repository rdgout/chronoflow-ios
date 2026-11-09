#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import LocalStore
    import SwiftUI

    @MainActor public struct SettingsPage<Content: View>: View {
        @Environment(\.locale) private var locale
        private let title: String
        private let identifier: String
        private let content: Content
        public init(_ title: String, identifier: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.identifier = identifier
            self.content = content()
        }
        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: PlanUITokens.space6) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PlanUITokens.space4)
                .padding(.top, PlanUITokens.space1)
                .padding(.bottom, SettingsTokens.pageBottom)
                .planPageRail()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ColorToken.background.color)
            .foregroundStyle(ColorToken.cardForeground.color).tint(ColorToken.primary.color)
            .font(Typography.screenBodyLg.font)
            .navigationTitle(SettingsStrings.text(title, language: language))
            .navigationBarTitleDisplayMode(.large)
            .background(SettingsNavigationStyle())
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
    }

    @MainActor public struct SettingsAccountView: View {
        @Environment(\.locale) private var locale
        private let store: SettingsPagesModel
        @State private var showingDelete = false
        public init(store: SettingsPagesModel) { self.store = store }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        public var body: some View {
            SettingsPage("Account", identifier: "settings.account.screen") {
                if let account = store.account {
                    Section {
                        NavigationLink(value: SettingsDestination.profile) {
                            VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                                Text(t("Profile"))
                                Text(account.name + " · " + account.email)
                                    .font(Typography.screenBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                            }
                        }.accessibilityIdentifier("settings.account.profile")
                        NavigationLink {
                            SettingsLanguageView()
                        } label: {
                            Label(t("Language"), systemImage: "globe")
                        }.accessibilityIdentifier("settings.account.language")
                    }
                    Section {
                        Button(t("Delete account"), role: .destructive) { showingDelete = true }
                            .accessibilityIdentifier("settings.account.delete")
                    }
                } else {
                    SettingsStoredState(loaded: store.loaded, failed: store.failure)
                }
            }.sheet(isPresented: $showingDelete) { SettingsDeleteAccountView(delete: store.deleteAccount) }
        }
    }

    @MainActor struct SettingsStoredState: View {
        @Environment(\.locale) private var locale
        var loaded: Bool
        var failed: Bool
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            if !loaded && !failed {
                ProgressView(t("Loading"))
            } else {
                Text(t("Your account isn't on this phone yet"))
                Text(t("We need a connection once to load your settings. After that they work offline."))
                    .foregroundStyle(ColorToken.mutedForeground.color)
            }
        }
    }

    @MainActor public struct SettingsProfileView: View {
        private let store: SettingsPagesModel
        public init(store: SettingsPagesModel) { self.store = store }
        public var body: some View {
            if let account = store.account {
                SettingsProfileEditor(account: account, save: store.saveProfile).id(account.id)
            } else {
                SettingsPage("Profile", identifier: "settings.profile.screen") {
                    SettingsStoredState(loaded: store.loaded, failed: store.failure)
                }
            }
        }
    }

    @MainActor private struct SettingsProfileEditor: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsProfileModel
        private let account: AccountRecord
        init(account: AccountRecord, save: @escaping @MainActor (String) async throws -> Void) {
            self.account = account
            _model = State(initialValue: SettingsProfileModel(account: account, save: save))
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            SettingsPage("Profile", identifier: "settings.profile.screen") {
                Section {
                    TextField(t("Name"), text: $model.name).textContentType(.name)
                        .accessibilityIdentifier("settings.profile.name")
                    LabeledContent(t("Email"), value: model.email)
                        .accessibilityIdentifier("settings.profile.email")
                }.disabled(model.busy)
                if let error = model.errorKey {
                    Text(t(error)).foregroundStyle(ColorToken.destructive.color)
                        .accessibilityIdentifier("settings.profile.error")
                }
                Section {
                    Button(t("Save changes")) { Task { await model.submit() } }
                        .disabled(model.busy).accessibilityIdentifier("settings.profile.save")
                    if model.saved {
                        Text(t("Saved on this phone · syncs when you're online"))
                            .foregroundStyle(ColorToken.mutedForeground.color)
                            .accessibilityIdentifier("settings.profile.saved")
                    }
                }
            }.onChange(of: account) { _, value in model.receive(value) }
        }
    }
#endif

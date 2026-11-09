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
        private let spacing: CGFloat
        public init(
            _ title: String, identifier: String, spacing: CGFloat = PlanUITokens.space6,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.identifier = identifier
            self.spacing = spacing
            self.content = content()
        }
        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
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
            .settingsFont(Typography.screenBodyLg)
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
        @Environment(SettingsDevicePreferences.self) private var device
        public init(store: SettingsPagesModel) { self.store = store }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        public var body: some View {
            SettingsPage("Account", identifier: "settings.account.screen") {
                if let account = store.account {
                    SettingsCard(rows: true) {
                        NavigationLink(value: SettingsDestination.profile) {
                            SettingsRow(
                                title: t("Profile"), subtitle: account.name + " · " + account.email, symbol: "person")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.account.profile")
                        SettingsDivider()
                        NavigationLink {
                            SettingsLanguageView()
                        } label: {
                            SettingsRow(title: t("Language"), subtitle: languageSubtitle, symbol: "globe")
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.account.language")
                    }
                    SettingsCard(rows: true) {
                        Button {
                            showingDelete = true
                        } label: {
                            Label(t("Delete account"), systemImage: "trash")
                                .settingsFont(Typography.settingsRow)
                                .frame(
                                    maxWidth: .infinity, minHeight: SettingsTokens.destructiveRowHeight,
                                    alignment: .leading
                                )
                                .padding(.horizontal, PlanUITokens.space4)
                                .foregroundStyle(ColorToken.destructive.color).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.account.delete")
                    }
                } else {
                    SettingsStoredState(loaded: store.loaded, failed: store.failure) { Task { await store.retry() } }
                }
            }.sheet(isPresented: $showingDelete) {
                SettingsDeleteAccountView(delete: store.deleteAccount)
            }
        }
        private var languageSubtitle: String {
            if device.language == .system {
                return SettingsStrings.text(
                    "Phone language ({{language}})",
                    language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                    [
                        "language": t(
                            device.resolvedLocale().language.languageCode?.identifier == "nl" ? "Nederlands" : "English"
                        )
                    ])
            }
            return t(device.language == .nl ? "Nederlands" : "English")
        }
    }

    @MainActor struct SettingsStoredState: View {
        @Environment(\.locale) private var locale
        var loaded: Bool
        var failed: Bool
        var retry: (() -> Void)? = nil
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            if !loaded && !failed {
                SettingsLoadingRows().accessibilityLabel(t("Loading"))
            } else {
                VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                    Text(t("Your account isn't on this phone yet")).settingsFont(Typography.screenCardTitle)
                    Text(t("We need a connection once to load your settings. After that they work offline."))
                        .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
                    if let retry {
                        AuthButton(
                            t("Try again"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight, action: retry)
                    }
                }
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
                    SettingsStoredState(loaded: store.loaded, failed: store.failure) { Task { await store.retry() } }
                }
            }
        }
    }

    @MainActor private struct SettingsProfileEditor: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsProfileModel
        @FocusState private var focus: String?
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
                SettingsCard {
                    AuthField(
                        t("Name"), text: $model.name, error: model.errorKey.map(t), identifier: "settings.profile.name",
                        contentType: .name, submitLabel: .done, focus: $focus
                    ) {
                        focus = nil
                    }
                    SettingsReadOnlyField(title: t("Email"), value: model.email)
                        .accessibilityIdentifier("settings.profile.email")
                }.disabled(model.busy)
                VStack(spacing: PlanUITokens.space2) {
                    AuthButton(t("Save changes"), busy: model.busy, minimumHeight: PlanUITokens.actionMinHeight) {
                        focus = nil
                        Task { await model.submit() }
                    }.disabled(model.busy).accessibilityIdentifier("settings.profile.save")
                    if model.saved {
                        HStack(spacing: SettingsTokens.pillGap) {
                            Image(systemName: "icloud.slash").accessibilityHidden(true)
                            Text(t("Saved on this phone · syncs when you're online"))
                                .accessibilityIdentifier("settings.profile.saved")
                        }.settingsFont(Typography.settingsHint).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                }
            }.onChange(of: account) { _, value in model.receive(value) }
        }
    }
#endif

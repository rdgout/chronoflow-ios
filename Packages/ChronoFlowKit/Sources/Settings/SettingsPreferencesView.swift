#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import LocalStore
    import PlanCore
    import PlanUI
    import Reminders
    import SwiftUI

    @MainActor public struct SettingsPreferencesView: View {
        private let store: SettingsPagesModel
        private let reminderPermission: @MainActor () async -> ReminderPermission
        public init(
            store: SettingsPagesModel, reminderPermission: @escaping @MainActor () async -> ReminderPermission
        ) {
            self.store = store
            self.reminderPermission = reminderPermission
        }
        public var body: some View {
            if let value = store.settings["preferences"] {
                SettingsPreferencesEditor(
                    value: value,
                    reminders: store.settings["reminders"].flatMap {
                        try? JSONDocument.encoding($0).decode(ReminderSettings.self)
                    },
                    reminderPermission: reminderPermission
                ) { patch in
                    try await store.enqueue(.settings(section: .preferences, patch: patch))
                }
            } else {
                SettingsPage("Preferences", identifier: "settings.preferences.screen") {
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure) {
                        Task { await store.retry() }
                    }
                }
            }
        }
    }
    @MainActor private struct SettingsPreferencesEditor: View {
        @Environment(\.locale) private var locale
        @Environment(\.scenePhase) private var scenePhase
        @Environment(SettingsDevicePreferences.self) private var device
        @State private var model: SettingsPreferencesModel
        @State private var permission: ReminderPermission?
        let value: JSONObject
        let reminders: ReminderSettings?
        let reminderPermission: @MainActor () async -> ReminderPermission
        init(
            value: JSONObject, reminders: ReminderSettings?,
            reminderPermission: @escaping @MainActor () async -> ReminderPermission,
            save: @escaping @MainActor (JSONObject) async throws -> Void
        ) {
            self.value = value
            self.reminders = reminders
            self.reminderPermission = reminderPermission
            _model = State(initialValue: SettingsPreferencesModel(value: value, save: save))
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            @Bindable var device = device
            SettingsPage("Preferences", identifier: "settings.preferences.screen") {
                SettingsCard {
                    SettingsEyebrow(title: t("Appearance"))
                    SettingsRadioGroup(
                        title: t("Theme"),
                        options: [
                            SettingsOption(id: "system", title: t("System")),
                            SettingsOption(id: "light", title: t("Light")),
                            SettingsOption(id: "dark", title: t("Dark")),
                        ],
                        selection: Binding(
                            get: { device.theme.rawValue },
                            set: {
                                if let value = SettingsDevicePreferences.Theme(rawValue: $0) { device.theme = value }
                            }), identifier: "settings.preferences.theme")
                    SettingsRadioGroup(
                        title: t("Time format"),
                        options: [
                            SettingsOption(id: "24", title: t("24-hour (14:30)")),
                            SettingsOption(id: "12", title: t("12-hour (2:30 PM)")),
                        ],
                        selection: Binding(
                            get: { model.value["timeFormat"]?.string ?? "24" },
                            set: { value in Task { await model.setTimeFormat(value) } }),
                        identifier: "settings.preferences.timeFormat")
                }
                VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                    VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                        SettingsEyebrow(title: t("Timeline categories"))
                        Text(t("Hide a category to keep your timeline calmer. Its steps stay in your plan."))
                            .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    SettingsCard(rows: true) {
                        ForEach(Array(SettingsTimelineGroup.all.enumerated()), id: \.element.title) { index, group in
                            if index > 0 { SettingsDivider() }
                            Toggle(
                                isOn: Binding(
                                    get: { model.shown(group) },
                                    set: { shown in Task { await model.setShown(shown, group: group) } })
                            ) {
                                HStack(spacing: PlanUITokens.space3) {
                                    CategorySwatch(swatch(group), size: .small)
                                    Text(t(group.title)).settingsFont(Typography.screenBodyLg)
                                }
                            }.padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                                .frame(minHeight: SettingsTokens.counterHeight)
                                .accessibilityIdentifier("settings.preferences.\(group.title)")
                        }
                    }
                }
                SettingsCard(rows: true) {
                    NavigationLink(value: SettingsDestination.reminders) {
                        SettingsRow(
                            title: ReminderStrings.text(
                                "Connectivity & reminders",
                                language: locale.language.languageCode?.identifier == "nl" ? .nl : .en),
                            subtitle: remindersSubtitle, symbol: "bell")
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.preferences.reminders")
                    SettingsDivider()
                    Button {
                        model.startWalkthroughReplay()
                    } label: {
                        SettingsRow(
                            title: t("Replay walkthrough"), subtitle: t("The short tour from your first trip"),
                            symbol: "arrow.counterclockwise", chevron: false)
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.preferences.replay")
                }
                if model.failure { SettingsError(title: t("We couldn't save your change. Please try again.")) }
            }.onChange(of: value) { _, value in model.receive(value) }
                .task { permission = await reminderPermission() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { permission = await reminderPermission() } }
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { model.walkthrough != nil },
                        set: { if !$0 { model.dismissWalkthroughReplay() } })
                ) {
                    if let walkthrough = model.walkthrough {
                        WalkthroughView(model: walkthrough)
                            .id(ObjectIdentifier(walkthrough))
                            .toolbar(.hidden, for: .navigationBar, .tabBar)
                    }
                }
        }
        private var remindersSubtitle: String? {
            guard let reminders, let permission else { return nil }
            return permission.remindersActive(reminders)
                ? SettingsStrings.text(
                    "On, {{minutes}} min ahead · works offline",
                    language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                    ["minutes": String(reminders.leadMin)])
                : t("Off · works offline")
        }
        private func swatch(_ group: SettingsTimelineGroup) -> BlockType {
            switch group.title {
            case "Sleep": .sleep
            case "Light": .seekLight
            case "Caffeine": .caffeineServing
            default: .flight
            }
        }

    }

    @MainActor public struct SettingsLanguageView: View {
        @Environment(\.locale) private var locale
        @Environment(SettingsDevicePreferences.self) private var device
        @State private var saved = false
        public init() {}
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        public var body: some View {
            @Bindable var device = device
            SettingsPage("Language", identifier: "settings.language.screen") {
                Text(
                    t(
                        "ChronoFlow follows your phone's language, and uses English if your phone is set to a language we don't offer yet. Pick a language here only if you want something different."
                    )
                )
                .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
                SettingsRadioGroup(
                    options: [
                        SettingsOption(
                            id: "system", title: t("Phone language"),
                            hint: SettingsStrings.text(
                                "Now {{language}} · changes with your phone",
                                language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                                [
                                    "language": t(
                                        Locale.current.language.languageCode?.identifier == "nl"
                                            ? "Nederlands" : "English")
                                ])),
                        SettingsOption(id: "en", title: t("English"), hint: t("Always English")),
                        SettingsOption(id: "nl", title: t("Nederlands"), hint: t("Always Dutch")),
                    ],
                    selection: Binding(
                        get: { device.language.rawValue },
                        set: {
                            if let choice = SettingsDevicePreferences.LanguageChoice(rawValue: $0) {
                                device.language = choice
                            }
                        }), cards: true, identifier: "settings.language.choice")
            }.onChange(of: device.language) { _, _ in saved = true }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if saved {
                        SettingsToast(
                            title: t(
                                device.language == .system
                                    ? "Saved. ChronoFlow follows your phone."
                                    : device.language == .en
                                        ? "Saved. The app is in English." : "Saved. The app is in Dutch."),
                            identifier: "settings.language.saved")
                    }
                }
        }
    }
#endif

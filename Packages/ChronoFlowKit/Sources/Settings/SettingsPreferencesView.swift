#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import LocalStore
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
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure)
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
                Section(t("Appearance")) {
                    Picker(t("Theme"), selection: $device.theme) {
                        Text(t("System")).tag(SettingsDevicePreferences.Theme.system)
                        Text(t("Light")).tag(SettingsDevicePreferences.Theme.light)
                        Text(t("Dark")).tag(SettingsDevicePreferences.Theme.dark)
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.preferences.theme")
                    Picker(
                        t("Time format"),
                        selection: Binding(
                            get: { model.value["timeFormat"]?.string ?? "24" },
                            set: { value in
                                Task { await model.setTimeFormat(value) }
                            })
                    ) {
                        Text(t("24-hour (14:30)")).tag("24")
                        Text(t("12-hour (2:30 PM)")).tag("12")
                    }.pickerStyle(.menu).accessibilityIdentifier("settings.preferences.timeFormat")
                }
                Section {
                    ForEach(SettingsTimelineGroup.all, id: \.title) { group in
                        Toggle(
                            t(group.title),
                            isOn: Binding(
                                get: { model.shown(group) },
                                set: { shown in
                                    Task { await model.setShown(shown, group: group) }
                                })
                        ).accessibilityIdentifier("settings.preferences.\(group.title)")
                    }
                } header: {
                    Text(t("Timeline categories"))
                } footer: {
                    Text(t("Hide a category to keep your timeline calmer. Its steps stay in your plan."))
                }
                Section {
                    NavigationLink(value: SettingsDestination.reminders) {
                        VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                            Label(
                                ReminderStrings.text(
                                    "Connectivity & reminders",
                                    language: locale.language.languageCode?.identifier == "nl" ? .nl : .en),
                                systemImage: "bell")
                            if let reminders, let permission {
                                Text(
                                    permission.remindersActive(reminders)
                                        ? SettingsStrings.text(
                                            "On, {{minutes}} min ahead · works offline",
                                            language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                                            ["minutes": String(reminders.leadMin)])
                                        : t("Off · works offline")
                                ).font(Typography.screenBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                            }
                        }
                    }.accessibilityIdentifier("settings.preferences.reminders")
                    Button {
                        model.startWalkthroughReplay()
                    } label: {
                        VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                            Label(t("Replay walkthrough"), systemImage: "arrow.counterclockwise")
                            Text(t("The short tour from your first trip")).font(Typography.screenBody.font)
                                .foregroundStyle(ColorToken.mutedForeground.color)
                        }
                    }.accessibilityIdentifier("settings.preferences.replay")
                }
                if model.failure {
                    Text(t("We couldn't save your change. Please try again.")).foregroundStyle(
                        ColorToken.destructive.color)
                }
                if model.saved {
                    Text(t("Saved on this phone · syncs when you're online")).accessibilityIdentifier(
                        "settings.preferences.saved")
                }
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
                    ))
                Picker(t("Language"), selection: $device.language) {
                    Text(t("Phone language")).tag(SettingsDevicePreferences.LanguageChoice.system)
                    Text(t("English")).tag(SettingsDevicePreferences.LanguageChoice.en)
                    Text(t("Dutch")).tag(SettingsDevicePreferences.LanguageChoice.nl)
                }.pickerStyle(.inline).accessibilityIdentifier("settings.language.choice")
                if saved {
                    Text(
                        t(
                            device.language == .system
                                ? "Saved. ChronoFlow follows your phone."
                                : device.language == .en
                                    ? "Saved. The app is in English." : "Saved. The app is in Dutch.")
                    )
                    .accessibilityIdentifier("settings.language.saved")
                }
            }.onChange(of: device.language) { _, _ in saved = true }
        }
    }
#endif

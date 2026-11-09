#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import Reminders
    import SwiftUI
    import UIKit

    @MainActor public struct RemindersView: View {
        @Environment(\.locale) private var locale
        @Environment(\.scenePhase) private var scenePhase
        @Bindable private var model: RemindersModel
        public init(model: RemindersModel) { self.model = model }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { ReminderStrings.text(key, language: language) }

        public var body: some View {
            SettingsPage("Connectivity & reminders", identifier: "reminders.screen") {
                SettingsCard {
                    VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                        Text(t("Reminders on this phone")).settingsFont(Typography.screenSectionTitle)
                        Text(
                            t(
                                "A nudge before each step in your plan. Reminders are scheduled on this phone, so they arrive without a connection. Each device has its own setting."
                            )
                        )
                        .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    if model.permission == .undetermined {
                        VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                            Text(
                                t(
                                    "Reminders are off. When you turn them on, your phone asks once whether ChronoFlow may send notifications."
                                )
                            )
                            .settingsFont(Typography.screenBody)
                            AuthButton(t("Turn on reminders"), minimumHeight: PlanUITokens.actionMinHeight) {
                                Task { await model.requestPermission() }
                            }
                            .disabled(model.busy || model.settings == nil).accessibilityIdentifier("reminders.ask")
                        }
                    } else if model.permission == .unsupported {
                        AuthNotice(
                            title: t("This device can't show reminders."),
                            message: t("You can still follow every step in your plan.")
                        ).accessibilityElement(children: .contain).accessibilityIdentifier("reminders.unsupported")
                    } else if model.permission != nil {
                        Toggle(
                            t("Push reminders"),
                            isOn: Binding(
                                get: { model.active }, set: { enabled in Task { await model.setEnabled(enabled) } })
                        )
                        .settingsFont(Typography.settingsRow)
                        .frame(minHeight: SettingsTokens.promptFieldHeight)
                        .disabled(model.permission != .granted || model.busy || model.settings == nil)
                        .accessibilityIdentifier("reminders.enabled")
                    }
                    if model.permission == .blocked {
                        VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                            AuthNotice(
                                title: t("Notifications are blocked for ChronoFlow."),
                                message: t("Allow them in your phone's settings to get reminders."), tone: .warning
                            )
                            .accessibilityIdentifier("reminders.blocked")
                            VStack(alignment: .leading, spacing: SettingsTokens.rowVertical) {
                                ForEach(instructions.indices, id: \.self) { index in
                                    HStack(alignment: .top, spacing: SettingsTokens.rowVertical) {
                                        Text(ReminderStrings.text("{{count}}", language: language, count: index + 1))
                                            .settingsFont(Typography.screenMeta).fontWeight(.semibold).monospacedDigit()
                                            .frame(width: PlanUITokens.space6, height: PlanUITokens.space6)
                                            .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                                        Text(instruction(index)).settingsFont(Typography.screenBody)
                                    }
                                }
                            }.padding(.leading, PlanUITokens.space1)
                            AuthButton(
                                t("Open phone settings"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight
                            ) {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }.accessibilityIdentifier("reminders.openSettings")
                        }
                    }
                    if model.active {
                        VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                            SettingsDivider()
                            Picker(
                                t("Remind me ahead by"),
                                selection: Binding(
                                    get: { model.settings?.leadMin ?? 30 },
                                    set: { minutes in Task { await model.setLead(minutes) } })
                            ) {
                                Text(t("15 min")).tag(15)
                                Text(t("30 min")).tag(30)
                                Text(t("1 hour")).tag(60)
                            }.disabled(model.busy).accessibilityIdentifier("reminders.lead")
                        }
                    }
                }
            }
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refreshPermission() } }
            }
            .onDisappear { model.stop() }
        }
        private func instruction(_ index: Int) -> AttributedString {
            var result = AttributedString(t(instructions[index]))
            for key in ["Settings", "Notifications", "ChronoFlow", "Allow notifications"] {
                if let range = result.range(of: t(key)) { result[range].font = Typography.screenLabel.font }
            }
            return result
        }
        private var instructions: [String] {
            [
                "Open your phone's Settings.", "Tap Notifications, then ChronoFlow.", "Turn on Allow notifications.",
                "Come back here. Reminders switch on by themselves.",
            ]
        }
    }

    @MainActor public struct FirstTripRemindersSheet: View {
        @Environment(\.locale) private var locale
        private let model: RemindersModel
        private let close: () -> Void
        public init(model: RemindersModel, close: @escaping () -> Void) {
            self.model = model
            self.close = close
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { ReminderStrings.text(key, language: language) }
        public var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: PlanUITokens.space4) {
                        Image(systemName: "bell").font(.system(size: PlanUITokens.walkthroughContentGap))
                            .foregroundStyle(ColorToken.dawnText.color)
                            .frame(width: PlanUITokens.space14, height: PlanUITokens.space14)
                            .background(ColorToken.dawn.color, in: Circle()).accessibilityHidden(true)
                        Text(t("Turn on reminders?")).settingsFont(Typography.screenCardTitle)
                        Text(
                            t(
                                "Reminders are off. When you turn them on, your phone asks once whether ChronoFlow may send notifications."
                            )
                        )
                        .settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
                        Button {
                            Task {
                                await model.requestPermission()
                                if model.failure == nil { close() }
                            }
                        } label: {
                            Text(t("Turn on reminders")).frame(maxWidth: .infinity).frame(
                                minHeight: PlanUITokens.wizardButtonHeight)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .disabled(model.busy || model.settings == nil).accessibilityIdentifier(
                                "reminders.firstTrip.enable")
                        Button(action: close) {
                            Text(t("Not now")).frame(maxWidth: .infinity).frame(minHeight: AuthTokens.touch)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reminders.firstTrip.notNow")
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(PlanUITokens.space6)
                        .planPageRail()
                }.background(ColorToken.background.color).foregroundStyle(ColorToken.foreground.color).tint(
                    ColorToken.primary.color
                )
                .accessibilityElement(children: .contain).accessibilityIdentifier("reminders.firstTrip")
                .task { await model.start() }.onDisappear { model.stop() }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).planPageSafeArea()
        }
    }
#endif

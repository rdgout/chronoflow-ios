#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    @MainActor public struct SettingsBodyClockView: View {
        private let store: SettingsPagesModel
        public init(store: SettingsPagesModel) { self.store = store }
        public var body: some View {
            if let answers = store.settings["bodyClock"] {
                SettingsBodyClockEditor(answers: answers, readiness: store.settings["readiness"]) { patch in
                    try await store.enqueue(.settings(section: .bodyClock, patch: patch))
                }
            } else {
                SettingsPage("Body clock", identifier: "settings.bodyClock.screen") {
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure)
                }
            }
        }
    }

    @MainActor private struct SettingsBodyClockEditor: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsBodyClockModel
        @State private var selectedTime: ClockSelection?
        private struct ClockSelection: Identifiable {
            let id: String
            let title: String
            let value: String?
        }
        private let answers: JSONObject
        private let readiness: JSONObject?
        init(answers: JSONObject, readiness: JSONObject?, save: @escaping @MainActor (JSONObject) async throws -> Void)
        {
            self.answers = answers
            self.readiness = readiness
            _model = State(initialValue: SettingsBodyClockModel(answers: answers, save: save))
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            ScrollViewReader { reader in
                SettingsPage("Body clock", identifier: "settings.bodyClock.screen") {
                    Text(t("Every plan is built from these answers. Changes save automatically."))
                    if let readiness {
                        SettingsReadinessView(value: readiness) {
                            reader.scrollTo(firstMissing(readiness), anchor: .top)
                        }
                    }
                    about
                    sleep
                    caffeine
                    light
                    health
                    if model.failure {
                        Text(t("We couldn't save your change. Please try again.")).foregroundStyle(
                            ColorToken.destructive.color)
                    }
                }
            }.onChange(of: answers) { _, value in model.receive(value) }
                .sheet(item: $selectedTime) { selection in
                    SettingsClockPicker(title: t(selection.title), value: selection.value) { value in
                        Task { await model.change(.sleep, [selection.id: .string(value)]) }
                    }
                }
        }
        private var about: some View {
            Section {
                choice(
                    .about, "chronotype", "When do you naturally feel most awake?",
                    [
                        ("early", "Early bird"), ("intermediate", "In between"), ("late", "Night owl"),
                        ("", "Not sure"),
                    ])
                choice(
                    .about, "ageBand", "Your age",
                    [("under_18", "Under 18"), ("18_64", "18–64"), ("65_plus", "65 or older")])
            } header: {
                groupHeader(.about)
            }
        }
        private var sleep: some View {
            Section {
                Text(t("On a normal work or school day.")).foregroundStyle(ColorToken.mutedForeground.color)
                time("habitualBed", "Usual bedtime")
                time("habitualWake", "Usual wake time")
                choice(
                    .sleep, "freeDayStatus", "Do your free days follow the same schedule?",
                    [("same_as_workdays", "Yes"), ("declared", "No")])
                if model.answers["freeDayStatus"]?.string == "declared" {
                    time("freeDayBed", "Free-day bedtime")
                    time("freeDayWake", "Free-day wake time")
                }
            } header: {
                groupHeader(.sleep)
            }
        }
        private var caffeine: some View {
            Section {
                choice(
                    .caffeine, "caffeineHabit", "Do you usually drink caffeine?",
                    [("cups", "Yes"), ("non_user", "No")])
                if model.answers["caffeineHabit"]?.string == "cups" {
                    Text(t("What do you drink on a normal day?"))
                    ForEach(
                        [
                            ("cupsFilterCoffee", "Coffee"), ("cupsTea", "Tea"), ("cupsCola", "Soft drinks"),
                            ("cupsEnergyDrink", "Energy drinks"),
                        ], id: \.0
                    ) { key, title in
                        Stepper(
                            value: Binding(
                                get: { count(key) },
                                set: { value in
                                    Task { await model.change(.caffeine, [key: .number(Decimal(value))]) }
                                }), in: 0...20
                        ) {
                            LabeledContent(t(title), value: String(count(key)))
                        }.accessibilityIdentifier("settings.bodyClock.\(key)")
                    }
                    error("cupsFilterCoffee")
                }
                yesNo(.caffeine, "caffeineSensitive", "Does caffeine affect you strongly?")
                yesNo(.health, "caffeineRuledOut", "Have you been told to avoid caffeine?")
                yesNo(.caffeine, "oralContraception", "Do you use oral contraception?")
            } header: {
                groupHeader(.caffeine)
            }
        }
        private var light: some View {
            Section {
                Text(t("Optional. If you have any of these, your plan can use them."))
                choice(
                    .light, "lightDevice", "Do you have a light box, light visor or light glasses?",
                    [("none", "None"), ("box", "Light box or visor"), ("glasses", "Light glasses")])
                choice(
                    .light, "blueBlockers", "Blue-blocking glasses",
                    [("no", "No"), ("unrated", "Yes, rating unknown"), ("rated", "Yes, I know the rating")])
                if model.answers["blueBlockers"]?.string == "rated" {
                    TextField(
                        t("Rating (mDFD)"),
                        text: Binding(
                            get: { model.answers["blueBlockerMdfd"]?.string ?? "" },
                            set: { value in
                                Task { await model.change(.light, ["blueBlockerMdfd": .string(value)]) }
                            })
                    ).keyboardType(.decimalPad).accessibilityIdentifier("settings.bodyClock.blueBlockerMdfd")
                    error("blueBlockerMdfd")
                }
            } header: {
                groupHeader(.light)
            }
        }
        private var health: some View {
            Section {
                Text(t("Your answers help tailor the timing advice. They are stored in your account."))
                yesNo(.health, "pregnancy", "Are you pregnant or breastfeeding?")
                yesNo(.health, "bipolar", "Do you have bipolar disorder?")
                yesNo(
                    .health, "eyeDisease",
                    "Do you have an eye disease, or take medicine that makes your eyes sensitive to light?")
                yesNo(
                    .health, "vte",
                    "Do you have a risk factor for blood clots, such as a past clot or a clotting disorder?")
                yesNo(
                    .health, "shiftWork",
                    "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?"
                )
            } header: {
                groupHeader(.health)
            }
        }
        private func groupHeader(_ group: BodyClockGroup) -> some View {
            HStack {
                Text(t(group.title))
                Spacer()
                if model.saved.contains(group) {
                    Label {
                        Text(t("Saved"))
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(ColorToken.dawnText.color)
                            .accessibilityHidden(true)
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.bodyClock.saved.\(group.rawValue)")
                }
            }.accessibilityElement(children: .contain)
        }
        private func count(_ key: String) -> Int {
            if case .number(let value) = model.answers[key] { NSDecimalNumber(decimal: value).intValue } else { 0 }
        }
        @ViewBuilder private func error(_ key: String) -> some View {
            if let error = model.errors[key] { Text(t(error)).foregroundStyle(ColorToken.destructive.color) }
        }
        private func choice(_ group: BodyClockGroup, _ key: String, _ title: String, _ options: [(String, String)])
            -> some View
        {
            Picker(
                t(title),
                selection: Binding(
                    get: { model.answers[key]?.string ?? "" },
                    set: { value in
                        var patch: [String: JSONValue] = [key: value.isEmpty ? .null : .string(value)]
                        if key == "freeDayStatus", value == "declared" {
                            patch["freeDayBed"] =
                                model.answers["freeDayBed"]?.string.map(JSONValue.string) ?? model.answers[
                                    "habitualBed"] ?? .null
                            patch["freeDayWake"] =
                                model.answers["freeDayWake"]?.string.map(JSONValue.string) ?? model.answers[
                                    "habitualWake"] ?? .null
                        }
                        Task { await model.change(group, patch) }
                    })
            ) {
                if !options.contains(where: { $0.0.isEmpty }) { Text(t("Not set")).tag("") }
                ForEach(options, id: \.0) { value, label in Text(t(label)).tag(value) }
            }.pickerStyle(.menu).id(key).accessibilityIdentifier("settings.bodyClock.\(key)")
                .overlay(alignment: .bottomLeading) { error(key) }
        }
        private func yesNo(_ group: BodyClockGroup, _ key: String, _ title: String) -> some View {
            Picker(
                t(title),
                selection: Binding(
                    get: {
                        if case .bool(let value) = model.answers[key] { return value ? "yes" : "no" }
                        return ""
                    },
                    set: { value in
                        Task { await model.change(group, [key: value.isEmpty ? .null : .bool(value == "yes")]) }
                    })
            ) {
                Text(t("Not set")).tag("")
                Text(t("Yes")).tag("yes")
                Text(t("No")).tag("no")
            }.pickerStyle(.menu).id(key).accessibilityIdentifier("settings.bodyClock.\(key)")
        }
        private func time(_ key: String, _ label: String) -> some View {
            Button {
                selectedTime = ClockSelection(id: key, title: label, value: model.answers[key]?.string)
            } label: {
                LabeledContent(t(label), value: model.answers[key]?.string ?? t("Not set"))
            }.pickerStyle(.menu).id(key).accessibilityIdentifier("settings.bodyClock.\(key)")
                .overlay(alignment: .bottomLeading) { error(key) }
        }
        private func firstMissing(_ readiness: JSONObject) -> String {
            guard case .array(let missing) = readiness["missing"], let first = missing.first?.object else {
                return "ageBand"
            }
            let raw = first["question"]?.string ?? "age_band"
            let parts = raw.split(separator: "_")
            return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        }
    }

    @MainActor private struct SettingsReadinessView: View {
        @Environment(\.locale) private var locale
        let value: JSONObject
        let firstMissing: () -> Void
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            Section {
                switch value["variant"]?.string {
                case "excluded":
                    Text(t("No plan available"))
                    Text(
                        t(
                            "Based on your health answers, light and caffeine timing may not be right for you, so we can't build a plan. Your doctor can tell you what's safe when you travel."
                        ))
                case "needs-answers":
                    Text(t("Almost ready"))
                    Button(t("Go to the first one"), action: firstMissing)
                case "ready":
                    Text(t("Required answers complete"))
                    Text(t("You can build a plan for any trip."))
                default: EmptyView()
                }
            }
        }
    }
#endif

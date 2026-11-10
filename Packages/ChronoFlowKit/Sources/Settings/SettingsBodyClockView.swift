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
                    SettingsStoredState(loaded: store.settingsLoaded, failed: store.failure) {
                        Task { await store.retry() }
                    }
                }
            }
        }
    }

    @MainActor private struct SettingsBodyClockEditor: View {
        @Environment(\.locale) private var locale
        @State private var model: SettingsBodyClockModel
        @State private var selectedTime: ClockSelection?
        @FocusState private var focus: String?
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
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        var body: some View {
            ScrollViewReader { reader in
                SettingsPage("Body clock", identifier: "settings.bodyClock.screen") {
                    Text(t("Every plan is built from these answers. Changes save automatically."))
                        .settingsFont(Typography.screenBodyLg).foregroundStyle(ColorToken.mutedForeground.color)
                    if let readiness {
                        SettingsReadinessView(value: readiness) { reader.scrollTo(firstMissing, anchor: .top) }
                    }
                    about
                    sleep
                    caffeine
                    light
                    health
                    if model.failure { SettingsError(title: t("We couldn't save your change. Please try again.")) }
                }
                .onChange(of: model.saved) { previous, saved in
                    if let group = saved.subtracting(previous).first {
                        reader.scrollTo(group, anchor: .top)
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
            SettingsCard {
                groupHeader(.about)
                SettingsRadioGroup(
                    title: t("When do you naturally feel most awake?"),
                    options: [
                        SettingsOption(
                            id: "early", title: t("Early bird"),
                            hint: t("You wake early without an alarm and fade in the evening.")),
                        SettingsOption(
                            id: "intermediate", title: t("In between"),
                            hint: t("Your energy follows a normal working day.")),
                        SettingsOption(
                            id: "late", title: t("Night owl"),
                            hint: t("You come alive late and find early starts hard.")),
                        SettingsOption(id: "", title: t("Not sure"), hint: t("We use your sleep times instead.")),
                    ], selection: stringBinding(.about, "chronotype"), cards: true,
                    identifier: "settings.bodyClock.chronotype")
                choice(
                    .about, "ageBand", "Your age",
                    [("under_18", "Under 18"), ("18_64", "18–64"), ("65_plus", "65 or older")])
            }
        }
        private var sleep: some View {
            SettingsCard {
                groupHeader(.sleep)
                caption("On a normal work or school day.")
                timePair([("habitualBed", "Usual bedtime"), ("habitualWake", "Usual wake time")])
                choice(
                    .sleep, "freeDayStatus", "Do your free days follow the same schedule?",
                    [("same_as_workdays", "Yes"), ("declared", "No")])
                if model.answers["freeDayStatus"]?.string == "declared" {
                    VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                        caption("On free days")
                        timePair([("freeDayBed", "Bedtime"), ("freeDayWake", "Wake time")])
                    }
                }
            }
        }
        private var caffeine: some View {
            SettingsCard {
                groupHeader(.caffeine)
                choice(
                    .caffeine, "caffeineHabit", "Do you usually drink caffeine?", [("cups", "Yes"), ("non_user", "No")])
                if model.answers["caffeineHabit"]?.string == "cups" { drinks }
                yesNo(
                    .caffeine, "caffeineSensitive", "Does caffeine affect you strongly?",
                    hint: "For example, one cup keeps you awake or makes you jittery.")
                preference(
                    .caffeine, "excludeCaffeine", "Leave caffeine out of my plan",
                    hint: "Your plan won't suggest any caffeine.")
            }
        }
        private var drinks: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                Text(t("What do you drink on a normal day?")).settingsFont(Typography.settingsRow)
                VStack(spacing: 0) {
                    ForEach(Array(drinkOptions.enumerated()), id: \.element.0) { index, drink in
                        if index > 0 { SettingsDivider() }
                        HStack(spacing: PlanUITokens.space1) {
                            Text(t(drink.1)).frame(maxWidth: .infinity, alignment: .leading)
                            counterButton(drink.0, drink.1, increase: false)
                            Text(
                                SettingsStrings.text(
                                    "{{count}} a day", language: language, ["count": String(count(drink.0))])
                            )
                            .settingsFont(Typography.screenBody).monospacedDigit().frame(minWidth: PlanUITokens.space16)
                            counterButton(drink.0, drink.1, increase: true)
                        }.padding(.leading, PlanUITokens.space4).padding(.trailing, PlanUITokens.space2)
                            .padding(.vertical, PlanUITokens.space2).frame(minHeight: SettingsTokens.counterHeight)
                            .accessibilityElement(children: .contain).accessibilityIdentifier(
                                "settings.bodyClock." + drink.0)
                    }
                }.overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl).strokeBorder(
                        ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
                error("cupsFilterCoffee")
            }
        }
        private var drinkOptions: [(String, String)] {
            [
                ("cupsFilterCoffee", "Coffee"), ("cupsTea", "Tea"), ("cupsCola", "Soft drinks"),
                ("cupsEnergyDrink", "Energy drinks"),
            ]
        }
        private func counterButton(_ key: String, _ title: String, increase: Bool) -> some View {
            Button {
                Task { await model.change(.caffeine, [key: .number(Decimal(count(key) + (increase ? 1 : -1)))]) }
            } label: {
                Image(systemName: increase ? "plus" : "minus").settingsFont(Typography.screenBodyLg)
                    .frame(width: AuthTokens.touch, height: AuthTokens.touch)
                    .overlay { Capsule().strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth) }
                    .contentShape(Capsule())
            }.buttonStyle(.plain).disabled(increase ? count(key) >= 20 : count(key) == 0)
                .accessibilityLabel(
                    SettingsStrings.text(
                        increase ? "More {{drink}}" : "Fewer {{drink}}", language: language,
                        ["drink": t(title).lowercased()])
                )
                .accessibilityIdentifier("settings.bodyClock." + key + (increase ? ".more" : ".fewer"))
        }
        private var light: some View {
            SettingsCard {
                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                    groupHeader(.light)
                    caption("Optional. If you have any of these, your plan can use them.")
                }
                choice(
                    .light, "lightDevice", "Do you have a light box, light visor or light glasses?",
                    [("none", "None"), ("box", "Light box or visor"), ("glasses", "Light glasses")])
                caption(
                    "Don't use a light box or light glasses if you have an eye disease, have had recent eye surgery or take medicine that makes your eyes sensitive to light. Ask your doctor first."
                )
                .accessibilityIdentifier("settings.bodyClock.lightNotice")
                choice(
                    .light, "blueBlockers", "Blue-blocking glasses",
                    [("no", "No"), ("unrated", "Yes, rating unknown"), ("rated", "Yes, I know the rating")])
                if model.answers["blueBlockers"]?.string == "rated" {
                    AuthField(
                        t("Rating (mDFD)"),
                        text: Binding(
                            get: { model.answers["blueBlockerMdfd"]?.string ?? "" },
                            set: { value in Task { await model.change(.light, ["blueBlockerMdfd": .string(value)]) } }),
                        error: model.errors["blueBlockerMdfd"].map(t),
                        hint: t("Melanopic daylight filtering density. It's on the box or the maker's website."),
                        identifier: "settings.bodyClock.blueBlockerMdfd", contentType: nil, keyboard: .decimalPad,
                        submitLabel: .done, focus: $focus
                    ) { focus = nil }
                }
            }
        }
        private var health: some View {
            SettingsCard {
                groupHeader(.health)
                yesNo(
                    .health, "shiftWork",
                    "In the past 14 days, have you worked night or rotating shifts, or had a very irregular sleep schedule?"
                )
                preference(
                    .health, "flightMovementBreaks", "Add movement breaks during long-flight sleep",
                    hint:
                        "Your plan breaks up long sleep on long flights with short movement breaks. If you're at higher risk of blood clots, choose this and ask your doctor about compression stockings and an aisle seat."
                )
                caption(
                    "ChronoFlow is intended for adults with a regular nightly sleep pattern. It does not offer a plan if you have recently done shift work, or do not usually sleep in one regular nightly episode."
                )
                caption(
                    "ChronoFlow is not suitable if you have bipolar disorder or have had a manic or hypomanic episode: sleep loss, bright light and long journeys can trigger mood episodes. Talk to your doctor before you travel."
                )
                .accessibilityIdentifier("settings.bodyClock.audienceNotice")
            }
        }
        private func preference(_ group: BodyClockGroup, _ key: String, _ title: String, hint: String) -> some View {
            Toggle(
                isOn: Binding(
                    get: { model.answers[key] == .bool(true) },
                    set: { value in Task { await model.change(group, [key: .bool(value)]) } }
                )
            ) {
                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                    Text(t(title)).settingsFont(Typography.settingsRow)
                    caption(hint)
                }
            }.tint(ColorToken.dawn.color).accessibilityIdentifier("settings.bodyClock." + key)
        }
        private func groupHeader(_ group: BodyClockGroup) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(t(group.title)).settingsFont(Typography.screenSectionTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: PlanUITokens.space2)
                if model.saved.contains(group) {
                    Label {
                        Text(t("Saved"))
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(ColorToken.dawnText.color).accessibilityHidden(
                            true)
                    }
                    .settingsFont(Typography.screenMeta).foregroundStyle(ColorToken.mutedForeground.color)
                    .accessibilityElement(children: .combine).accessibilityIdentifier(
                        "settings.bodyClock.saved." + group.rawValue)
                }
            }.accessibilityElement(children: .contain).id(group)
        }
        private func caption(_ key: String) -> some View {
            Text(t(key)).settingsFont(Typography.screenBody).foregroundStyle(ColorToken.mutedForeground.color)
        }
        private func count(_ key: String) -> Int {
            if case .number(let value) = model.answers[key] { NSDecimalNumber(decimal: value).intValue } else { 0 }
        }
        @ViewBuilder private func error(_ key: String) -> some View {
            if let error = model.errors[key] { SettingsError(title: t(error)) }
        }
        private func stringBinding(_ group: BodyClockGroup, _ key: String) -> Binding<String> {
            Binding(
                get: { model.answers[key]?.string ?? "" },
                set: { value in
                    var patch: [String: JSONValue] = [key: value.isEmpty ? .null : .string(value)]
                    if key == "freeDayStatus", value == "declared" {
                        patch["freeDayBed"] = model.answers["freeDayBed"] ?? model.answers["habitualBed"] ?? .null
                        patch["freeDayWake"] = model.answers["freeDayWake"] ?? model.answers["habitualWake"] ?? .null
                        if patch["freeDayBed"] == .null { patch["freeDayBed"] = model.answers["habitualBed"] ?? .null }
                        if patch["freeDayWake"] == .null {
                            patch["freeDayWake"] = model.answers["habitualWake"] ?? .null
                        }
                    }
                    Task { await model.change(group, patch) }
                })
        }
        private func choice(_ group: BodyClockGroup, _ key: String, _ title: String, _ options: [(String, String)])
            -> some View
        {
            question(key, title) {
                SettingsRadioGroup(
                    options: options.map { SettingsOption(id: $0.0, title: t($0.1)) },
                    selection: stringBinding(group, key), identifier: "settings.bodyClock." + key)
            }
        }
        private func yesNo(_ group: BodyClockGroup, _ key: String, _ title: String, hint: String? = nil) -> some View {
            question(key, title, hint: hint) {
                SettingsRadioGroup(
                    options: [SettingsOption(id: "yes", title: t("Yes")), SettingsOption(id: "no", title: t("No"))],
                    selection: Binding(
                        get: {
                            if case .bool(let value) = model.answers[key] { return value ? "yes" : "no" }
                            return ""
                        }, set: { value in Task { await model.change(group, [key: .bool(value == "yes")]) } }),
                    identifier: "settings.bodyClock." + key)
            }
        }
        private func question<Content: View>(
            _ key: String, _ title: String, hint: String? = nil, @ViewBuilder content: () -> Content
        ) -> some View {
            let missing = missingFields.contains(key)
            return VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                Text(t(title)).settingsFont(Typography.settingsRow)
                if missing { SettingsBadge(title: t("Needs an answer"), dawn: true) }
                if let hint { caption(hint) }
                content()
                error(key)
            }.padding(missing ? PlanUITokens.space3 : 0)
                .background {
                    if missing {
                        RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl).fill(
                            ColorToken.settingsWarningBackground.color
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl).strokeBorder(
                                ColorToken.settingsWarningBorder.color, lineWidth: AuthTokens.borderWidth)
                        }
                    }
                }.padding(.horizontal, missing ? -PlanUITokens.space3 : 0).id(key)
        }
        private func timePair(_ items: [(String, String)]) -> some View {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: PlanUITokens.space16 * 2), spacing: PlanUITokens.space3)],
                spacing: PlanUITokens.space3
            ) {
                ForEach(items, id: \.0) { key, label in
                    VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                        Button {
                            selectedTime = ClockSelection(
                                id: key,
                                title: key == "freeDayBed"
                                    ? "Free-day bedtime" : key == "freeDayWake" ? "Free-day wake time" : label,
                                value: model.answers[key]?.string)
                        } label: {
                            VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                                caption(label)
                                Text(model.answers[key]?.string ?? t("Not set")).settingsFont(Typography.settingsTime)
                                    .monospacedDigit()
                            }.frame(
                                maxWidth: .infinity,
                                minHeight: SettingsTokens.timeHeight - SettingsTokens.timeVertical * 2,
                                alignment: .leading
                            )
                            .padding(.horizontal, PlanUITokens.space4).padding(.vertical, SettingsTokens.timeVertical)
                            .background(
                                ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl).strokeBorder(
                                    ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.bodyClock." + key)
                        error(key)
                    }.id(key)
                }
            }
        }
        private var missingFields: [String] {
            guard case .array(let missing) = readiness?["missing"] else { return [] }
            return missing.map { item in
                let raw = item.object?["question"]?.string ?? "age_band"
                return raw.split(separator: "_").enumerated().map {
                    $0.offset == 0 ? String($0.element) : $0.element.capitalized
                }.joined()
            }
        }
        private var firstMissing: String {
            if let first = missingFields.first { return first }
            if case .array(let invalid) = readiness?["invalidSections"], let raw = invalid.first?.string,
                let group = BodyClockGroup(rawValue: raw)
            {
                return group.fields.first ?? "ageBand"
            }
            return "ageBand"
        }
    }

    private struct SettingsReadinessView: View {
        @Environment(\.locale) private var locale
        let value: JSONObject
        let firstMissing: () -> Void
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }
        private func count(_ key: String) -> Int { if case .array(let list) = value[key] { list.count } else { 0 } }
        var body: some View {
            if value["variant"]?.string == "excluded" {
                VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                    Label(t("No plan available"), systemImage: "exclamationmark.triangle").settingsFont(
                        Typography.settingsStrong)
                    if case .array(let lines) = value["exclusions"] {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            if let key = line.object?["key"]?.string {
                                Text(t(key)).settingsFont(Typography.screenBody)
                            }
                        }
                    }
                }.padding(PlanUITokens.space5).frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        ColorToken.settingsWarningBackground.color,
                        in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                            ColorToken.settingsWarningBorder.color, lineWidth: AuthTokens.borderWidth)
                    }
            } else if value["variant"]?.string == "needs-answers" {
                SettingsCard(spacing: PlanUITokens.space3) {
                    SettingsEyebrow(title: t("Almost ready"), dawn: true)
                    let missing = count("missing") + count("invalidSections")
                    let total = 2 + count("invalidSections")
                    Text(
                        SettingsStrings.text(
                            missing == 1
                                ? "We need 1 more answer before we can build a plan"
                                : "We need {{count}} more answers before we can build a plan", language: language,
                            ["count": String(missing)])
                    ).settingsFont(Typography.screenSectionTitle)
                    HStack(spacing: PlanUITokens.space2) {
                        Capsule().fill(ColorToken.muted.color)
                            .overlay(alignment: .leading) {
                                Capsule().fill(ColorToken.dawn.color)
                                    .frame(
                                        width: PlanUITokens.progressTrackWidth * CGFloat(max(0, total - missing))
                                            / CGFloat(total))
                            }.frame(width: PlanUITokens.progressTrackWidth, height: SettingsTokens.pillGap)
                            .accessibilityHidden(true)
                        Label(
                            SettingsStrings.text(
                                "{{done}}/{{total}} done", language: language,
                                ["done": String(max(0, total - missing)), "total": String(total)]),
                            systemImage: "checkmark"
                        )
                        .settingsFont(Typography.screenMeta).foregroundStyle(ColorToken.mutedForeground.color)
                        .monospacedDigit()
                    }
                    AuthButton(
                        t("Go to the first one"), kind: .secondary, minimumHeight: PlanUITokens.walkthroughDoneHeight,
                        action: firstMissing)
                }
            } else if ["ready", "adjusted"].contains(value["variant"]?.string ?? "") {
                SettingsCard {
                    HStack(spacing: PlanUITokens.space3) {
                        Image(systemName: "checkmark").frame(
                            width: SettingsTokens.rowDisc, height: SettingsTokens.rowDisc
                        )
                        .background(ColorToken.dawn.color, in: Circle()).foregroundStyle(
                            ColorToken.dawnForeground.color
                        ).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(
                                t(
                                    value["variant"] == .string("adjusted")
                                        ? "Your plan is adjusted for your preferences and age range"
                                        : "Required answers complete")
                            ).settingsFont(Typography.settingsStrong)
                            Text(
                                t("Your age range and shift-work answer are saved. You can add optional details below.")
                            ).settingsFont(Typography.screenBody)
                                .foregroundStyle(ColorToken.mutedForeground.color)
                        }
                    }
                    if value["variant"] == .string("adjusted"), case .array(let lines) = value["adjustments"] {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            if let key = line.object?["key"]?.string {
                                Text(t(key)).settingsFont(Typography.screenBody)
                            }
                        }
                    }
                }
            }
        }
    }
#endif

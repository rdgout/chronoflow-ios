#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    struct WizardAnswerSheet: View {
        @Environment(\.locale) private var locale
        @Bindable var model: MemberWizardModel
        let prompt: ApiReviewPrompt
        let question: String
        let title: String
        let fieldCopy: (FieldMessage) -> String
        @State private var values: [String: JSONValue] = [:]
        @State private var error: String?
        @State private var loaded = false
        @State private var busyPicker: BusyPicker?
        @State private var pendingBusyEnd: BusyPicker?
        private func t(_ key: String) -> String { WizardStrings.text(key, locale: locale) }
        private var optionField: String { prompt.kind == .room ? "stay.bed_available_mode" : prompt.fields.first ?? "" }
        private var options: [(JSONValue, String, String?)] {
            switch prompt.kind {
            case .seatSide:
                [
                    (.string("left"), "Window left", nil), (.string("right"), "Window right", nil),
                    (.null, "Aisle or not sure", "We plan without the window"),
                ]
            case .room: [(.string("arrival"), "When I land", nil), (.string("declared"), "From a time", nil)]
            case .lateCheckOut: [(.bool(true), "Yes", nil), (.bool(false), "No", nil)]
            case .freeDayTimes:
                [
                    (.string("same_as_workdays"), "Same as work days", nil),
                    (.string("declared"), "Different times", nil),
                ]
            case .lightDevice:
                [
                    (.string("none"), "None", nil), (.string("box"), "Light box", nil),
                    (.string("glasses"), "Light glasses", nil),
                ]
            case .blueBlockers:
                [
                    (.string("no"), "No", nil), (.string("rated"), "Yes, with a rating", nil),
                    (.string("unrated"), "Yes, no rating", nil),
                ]
            case .cups: [(.string("non_user"), "None", nil)]
            default: []
            }
        }
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                        Text(question).font(Typography.wizardRow.font).accessibilityIdentifier("wizard.answer.question")
                        if prompt.kind == .seatSide {
                            Text(route).font(Typography.wizardHint.font).foregroundStyle(
                                ColorToken.mutedForeground.color)
                        }
                        if !options.isEmpty { optionRows }
                        controls
                        if let error { errorLine(error, identifier: "wizard.answer.error") }
                    }.padding(PlanUITokens.space5).frame(maxWidth: .infinity, alignment: .leading)
                }.background(ColorToken.card.color).foregroundStyle(ColorToken.foreground.color)
                    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("Cancel")) { model.openPrompt(nil) }.accessibilityIdentifier(
                                "wizard.answer.cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("Done"), action: done).disabled(error != nil || missingTimes)
                                .accessibilityIdentifier("wizard.answer.done")
                        }
                    }
            }.tint(ColorToken.dawnText.color).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .accessibilityIdentifier("wizard.answer.\(prompt.kind.rawValue)")
                .onAppear(perform: load)
                .sheet(
                    item: $busyPicker,
                    onDismiss: {
                        busyPicker = pendingBusyEnd
                        pendingBusyEnd = nil
                    },
                    content: { picker in
                        WizardDateTimeSheet(
                            title: t(picker.start == nil ? "From" : "To"), localTime: busyLocalTime,
                            value: picker.value, minimum: picker.start?.addingTimeInterval(60)
                        ) { date in
                            if let start = picker.start {
                                saveBusyRange(index: picker.index, start: start, end: date)
                            } else {
                                let previousEnd = picker.index.flatMap {
                                    WizardDateTime.date(intervals[$0].object?["end_local"]?.string ?? "")
                                }
                                pendingBusyEnd = BusyPicker(
                                    index: picker.index, start: date,
                                    value: max(
                                        previousEnd ?? date.addingTimeInterval(3600), date.addingTimeInterval(60)))
                            }
                        }
                    })
        }
        private var legIndex: Int {
            (prompt.scope.journey == .return ? model.draft.form.returnBoundary : 0)
                + (prompt.scope.legIndex ?? prompt.scope.stayIndex ?? 0)
        }
        private var route: String {
            guard model.draft.form.legs.indices.contains(legIndex) else { return "" }
            let leg = model.draft.form.legs[legIndex]
            return leg.fromIata + " → " + leg.toIata
        }
        private var missingTimes: Bool {
            (prompt.kind == .freeDayTimes && values["free_day_status"] == .string("declared")
                && (!WizardDateTime.isTime(values["free_day_bed"]?.string)
                    || !WizardDateTime.isTime(values["free_day_wake"]?.string)))
                || (prompt.kind == .latestWake && !WizardDateTime.isTime(values["latest_wake"]?.string))
                || (prompt.kind == .room && values["stay.bed_available_mode"] == .string("declared")
                    && WizardDateTime.date(values["stay.bed_available_from_local"]?.string ?? "") == nil)
        }
        private func load() {
            guard !loaded else { return }
            loaded = true
            values = (try? WizardPresentation.promptAnswers(prompt, input: model.reviewInput)) ?? prompt.answer
            if prompt.target == .profile {
                for field in prompt.fields where values[field] == nil || values[field] == .null {
                    let parts = field.split(separator: "_")
                    let key =
                        String(parts.first ?? "")
                        + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
                    values[field] = model.draft.state.savedProfile?[key] ?? values[field]
                }
            }
            if case .number(let rating) = values["blue_blocker_mdfd"] {
                let formatter = NumberFormatter()
                formatter.locale = locale
                values["blue_blocker_mdfd"] = .string(formatter.string(from: NSDecimalNumber(decimal: rating)) ?? "")
            }
            if let message = WizardPresentation.promptFieldError(
                prompt, form: model.draft.form, errors: model.draft.fieldErrors)
            {
                error = fieldCopy(message)
            }
            #if DEBUG
                if let seedError = model.boardAnswerError { error = t(seedError) }
            #endif
        }
        private var optionRows: some View {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    if index > 0 { Divider().overlay(ColorToken.border.color) }
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        update(optionField, option.0)
                        if prompt.kind == .cups {
                            for field in WizardOptionalAnswer.drinkFields { update(field, .number(0)) }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t(option.1))
                                if let hint = option.2 {
                                    Text(t(hint)).font(Typography.wizardHint.font).foregroundStyle(
                                        ColorToken.mutedForeground.color)
                                }
                            }
                            Spacer(minLength: 0)
                            if values[optionField] == option.0 {
                                Image(systemName: "checkmark").foregroundStyle(ColorToken.dawnText.color)
                            }
                        }.padding(PlanUITokens.space4).frame(minHeight: PlanUITokens.wizardButtonHeight)
                    }.buttonStyle(.plain).accessibilityIdentifier("wizard.answer.option.\(index)")
                        .accessibilityAddTraits(values[optionField] == option.0 ? [.isSelected] : [])
                }
            }.font(Typography.wizardRow.font).background(
                ColorToken.background.color, in: RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius))
        }
        @ViewBuilder private var controls: some View {
            switch prompt.kind {
            case .room:
                if values["stay.bed_available_mode"] == .string("declared") {
                    WizardTimeControl(
                        label: t("wizard.room.from"),
                        value: Binding(
                            get: { values["stay.bed_available_from_local"]?.string ?? "" },
                            set: { time in
                                guard model.draft.form.legs.indices.contains(legIndex) else { return }
                                update(
                                    "stay.bed_available_from_local",
                                    .string(String(model.draft.form.legs[legIndex].arriveLocal.prefix(10)) + "T" + time)
                                )
                            }))
                }
            case .latestWake:
                time("Latest you can wake up", field: "latest_wake")
                    .datePickerStyle(.wheel).labelsHidden()
                    .frame(maxWidth: .infinity).frame(height: PlanUITokens.wizardTimeWheelHeight).clipped()
                    .background(
                        ColorToken.background.color, in: RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius).strokeBorder(
                            ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                    }
            case .freeDayTimes:
                if values["free_day_status"] == .string("declared") {
                    time("Bedtime", field: "free_day_bed")
                    time("Wake-up", field: "free_day_wake")
                }
            case .cups: drinks
            case .blueBlockers:
                if values["blue_blockers"] == .string("rated") {
                    HStack {
                        Text(t("Rating on the label"))
                        TextField(
                            t("Rating on the label"),
                            text: Binding(
                                get: { values["blue_blocker_mdfd"]?.string ?? "" },
                                set: { update("blue_blocker_mdfd", .string($0)) })
                        )
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
                            "wizard.answer.rating")
                    }
                }
            case .preDepartureBusyHours: busy
            default: EmptyView()
            }
        }
        private var drinks: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                Text(t("Cups a day")).font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                ForEach(Array(WizardOptionalAnswer.drinkFields.enumerated()), id: \.element) { index, field in
                    Stepper(
                        value: Binding(
                            get: {
                                if case .number(let number) = values[field] {
                                    return NSDecimalNumber(decimal: number).intValue
                                }
                                return 0
                            },
                            set: { count in
                                UISelectionFeedbackGenerator().selectionChanged()
                                update("caffeine_habit", .string("cups"))
                                update(field, .number(Decimal(count)))
                            }), in: 0...Int(prompt.shape.max ?? 20)
                    ) {
                        Text(t(["Coffee", "Tea", "Soft drinks", "Energy drinks"][index]))
                        Text(number(field)).monospacedDigit()
                    }.accessibilityIdentifier("wizard.answer.\(field)")
                }
            }.font(Typography.wizardRow.font).padding(PlanUITokens.space4).wizardCard()
        }
        private var intervals: [JSONValue] {
            if case .array(let rows) = values["pre_departure_busy_intervals"] { return rows }
            return []
        }
        private struct BusyPicker: Identifiable {
            let id = UUID()
            let index: Int?
            var start: Date?
            let value: Date
        }
        private var busyLocalTime: String {
            let city = model.draft.form.legs.first?.fromCity
            return city.map { WizardStrings.text("Time in {{city}}", locale: locale, arguments: ["city": $0]) }
                ?? t("Local time")
        }
        private var busy: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                if !intervals.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(intervals.indices, id: \.self) { index in
                            if index > 0 { Divider().overlay(ColorToken.border.color) }
                            HStack(spacing: PlanUITokens.space2) {
                                Button {
                                    openBusyPicker(index: index)
                                } label: {
                                    Text(busyRangeText(index)).monospacedDigit()
                                        .frame(maxWidth: .infinity, minHeight: AuthTokens.touch, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    var rows = intervals
                                    rows.remove(at: index)
                                    update("pre_departure_busy_intervals", .array(rows))
                                    update("pre_departure_busy_answered", .bool(true))
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: PlanUITokens.wizardStopGlyphSize))
                                        .foregroundStyle(ColorToken.mutedForeground.color)
                                        .frame(width: PlanUITokens.space8, height: PlanUITokens.space8)
                                        .background(Color.wizardPickerFill, in: Circle())
                                        .frame(minWidth: AuthTokens.touch, minHeight: AuthTokens.touch)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(
                                        WizardStrings.text(
                                            "Remove {{range}}", locale: locale,
                                            arguments: ["range": busyRangeText(index)])
                                    )
                                    .accessibilityIdentifier("wizard.answer.remove-busy.\(index)")
                            }.padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                        }
                    }.font(Typography.screenBodyLg.font)
                        .background(
                            ColorToken.background.color,
                            in: RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius).strokeBorder(
                                ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                        }
                }
                Button {
                    openBusyPicker(index: nil)
                } label: {
                    Label(t("Add busy hours"), systemImage: "plus")
                        .font(Typography.screenBodyLg.font).foregroundStyle(ColorToken.dawnText.color)
                        .frame(minHeight: AuthTokens.touch).padding(.horizontal, PlanUITokens.space1)
                }.buttonStyle(.plain).accessibilityIdentifier("wizard.answer.add-busy")
            }
        }
        private func busyRangeText(_ index: Int) -> String {
            guard let row = intervals[index].object,
                let start = row["start_local"]?.string, let startDate = WizardDateTime.date(start),
                let end = row["end_local"]?.string, let endDate = WizardDateTime.date(end)
            else { return t("Choose") }
            let endText =
                start.prefix(10) == end.prefix(10)
                ? String(end.suffix(5))
                : WizardDateTime.format(endDate, template: "EEE d MMM", locale: locale) + " · " + end.suffix(5)
            return WizardDateTime.format(startDate, template: "EEE d MMM", locale: locale)
                + " · " + start.suffix(5) + "–" + endText
        }
        private func openBusyPicker(index: Int?) {
            let start = index.flatMap { WizardDateTime.date(intervals[$0].object?["start_local"]?.string ?? "") }
            busyPicker = BusyPicker(
                index: index,
                value: start ?? WizardDateTime.date(model.draft.form.legs[0].departLocal) ?? Date())
        }
        private func saveBusyRange(index: Int?, start: Date, end: Date) {
            var rows = intervals
            let range: JSONValue = .object([
                "start_local": .string(WizardDateTime.string(start)),
                "end_local": .string(WizardDateTime.string(end)),
            ])
            if let index, rows.indices.contains(index) { rows[index] = range } else { rows.append(range) }
            update("pre_departure_busy_intervals", .array(rows))
            update("pre_departure_busy_answered", .bool(true))
        }
        private func time(_ key: String, field: String) -> some View {
            WizardTimeControl(
                label: t(key), value: Binding(get: { values[field]?.string ?? "" }, set: { update(field, .string($0)) })
            )
        }
        private func number(_ field: String) -> String {
            if case .number(let number) = values[field] { return NSDecimalNumber(decimal: number).stringValue }
            return "0"
        }
        private func update(_ field: String, _ value: JSONValue) {
            values[field] = value
            error = nil
        }
        private func done() {
            if let message = WizardOptionalAnswer.error(prompt, values: values) {
                error = t(message)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            if prompt.kind == .blueBlockers, values["blue_blockers"] == .string("rated") {
                values["blue_blocker_mdfd"] = .string(
                    (values["blue_blocker_mdfd"]?.string ?? "").replacingOccurrences(of: ",", with: "."))
            }
            do { try model.answerOptional(prompt, values: values) } catch {
                self.error = t("Choose one of the available options.")
            }
        }
    }
#endif

#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    struct WizardFlightDateTimeRow: View {
        @Environment(\.locale) private var locale
        let model: MemberWizardModel
        let index: Int
        let arrival: Bool
        @State private var component: Component?
        private enum Component: String, Identifiable {
            case date, time
            var id: String { rawValue }
        }
        private var value: String {
            arrival ? model.draft.form.legs[index].arriveLocal : model.draft.form.legs[index].departLocal
        }
        private var key: String { "legs.\(index)." + (arrival ? "arriveLocal" : "departLocal") }
        private var identifier: String { "wizard.\(index)." + (arrival ? "arrival" : "departure") }
        private var fallback: String { WizardDateTime.string(Date()) }
        private func t(_ key: String) -> String { WizardStrings.text(key, locale: locale) }

        var body: some View {
            WizardFlightRowLayout(spacing: PlanUITokens.space2, fillsWidth: true) {
                caption
                controls
            }
            .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
            .frame(minHeight: PlanUITokens.wizardFlightRowHeight)
            .popover(item: $component) { component in
                WizardNativePicker(
                    title: t(
                        arrival
                            ? (component == .date ? "Arrival date" : "Arrival time")
                            : (component == .date ? "Departure date" : "Departure time")),
                    value: WizardDateTime.date(value) ?? WizardDateTime.date(fallback)!, dateOnly: component == .date
                ) { picked in
                    let next = WizardDateTime.string(picked)
                    let current = WizardDateTime.date(value) == nil ? fallback : value
                    let combined =
                        component == .date
                        ? String(next.prefix(10)) + "T" + current.suffix(5)
                        : String(current.prefix(10)) + "T" + next.suffix(5)
                    model.setDateTime(combined, index: index, arrival: arrival)
                    UISelectionFeedbackGenerator().selectionChanged()
                    self.component = nil
                }
                .presentationCompactAdaptation(.popover)
            }
        }

        private var caption: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(t(arrival ? "Arrives" : "Departs")).font(Typography.wizardRow.font)
                let leg = model.draft.form.legs[index]
                let city = arrival ? leg.toCity ?? leg.toIata : leg.fromCity ?? leg.fromIata
                Text(WizardStrings.text("Time in {{city}}", locale: locale, arguments: ["city": city]))
                    .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
            }.fixedSize(horizontal: false, vertical: true)
        }

        private var controls: some View {
            WizardFlightRowLayout(spacing: PlanUITokens.space2) {
                dateControl
                timeControl
            }.buttonStyle(.plain)
                .environment(\.calendar, WizardDateTime.calendar).environment(
                    \.timeZone, WizardDateTime.calendar.timeZone
                )
        }

        private var dateControl: some View {
            ZStack {
                datePicker
                    .foregroundStyle(ColorToken.foreground.color)
                    .tint(ColorToken.foreground.color)
            }
            .overlay {
                RoundedRectangle(cornerRadius: PlanUITokens.radiusSm).strokeBorder(
                    ColorToken.destructive.color, lineWidth: AuthTokens.focusWidth
                )
                .opacity(model.draft.fieldErrors[key] == nil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }

        @ViewBuilder private var datePicker: some View {
            if let date = WizardDateTime.date(value) {
                DatePicker(
                    t(arrival ? "Arrival date" : "Departure date"), selection: binding(date, dateOnly: true),
                    displayedComponents: .date
                )
                .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier(identifier + ".date")
            } else {
                placeholder("Date") { component = .date }.accessibilityIdentifier(identifier + ".date")
                    .accessibilityLabel(t(arrival ? "Arrival date" : "Departure date"))
            }
        }

        @ViewBuilder private var timeControl: some View {
            if let date = WizardDateTime.date(value) {
                DatePicker(
                    t(arrival ? "Arrival time" : "Departure time"), selection: binding(date, dateOnly: false),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier(identifier + ".time")
            } else {
                placeholder("Time") { component = .time }.accessibilityIdentifier(identifier + ".time")
                    .accessibilityLabel(t(arrival ? "Arrival time" : "Departure time"))
            }
        }

        private func placeholder(_ key: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(t(key)).font(Typography.wizardRow.font).monospacedDigit()
                    .foregroundStyle(ColorToken.mutedForeground.color)
                    .padding(.horizontal, PlanUITokens.space3).padding(.vertical, PlanUITokens.wizardControlGap)
                    .background(Color.wizardPickerFill, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusSm))
            }
        }

        private func binding(_ date: Date, dateOnly: Bool) -> Binding<Date> {
            Binding(
                get: { WizardDateTime.date(value) ?? date },
                set: { picked in
                    let next = WizardDateTime.string(picked)
                    let combined =
                        dateOnly
                        ? String(next.prefix(10)) + "T" + value.suffix(5)
                        : String(value.prefix(10)) + "T" + next.suffix(5)
                    model.setDateTime(combined, index: index, arrival: arrival)
                    UISelectionFeedbackGenerator().selectionChanged()
                })
        }
    }

    private struct WizardNativePicker: View {
        @Environment(\.locale) private var locale
        let title: String
        let dateOnly: Bool
        let picked: (Date) -> Void
        @State private var value: Date

        init(title: String, value: Date, dateOnly: Bool, picked: @escaping (Date) -> Void) {
            self.title = title
            self.dateOnly = dateOnly
            self.picked = picked
            _value = State(initialValue: value)
        }

        var body: some View {
            VStack {
                DatePicker(title, selection: $value, displayedComponents: dateOnly ? .date : .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.calendar, WizardDateTime.calendar).environment(
                        \.timeZone, WizardDateTime.calendar.timeZone
                    )
                    .accessibilityIdentifier("wizard.native-picker")
                Button(WizardStrings.text("Done", locale: locale)) { picked(value) }
                    .accessibilityIdentifier("wizard.picker.done")
            }.padding(PlanUITokens.space4)
        }
    }
#endif

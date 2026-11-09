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
        @State private var showingPicker = false

        private var value: String {
            arrival ? model.draft.form.legs[index].arriveLocal : model.draft.form.legs[index].departLocal
        }
        private var key: String { "legs.\(index)." + (arrival ? "arriveLocal" : "departLocal") }
        private var identifier: String { "wizard.\(index)." + (arrival ? "arrival" : "departure") }
        private var title: String { t(arrival ? "Arrival" : "Departure") }
        private var displayedValue: String {
            value.isEmpty ? t("Choose") : WizardDateTime.formatLocal(value, locale: locale) ?? t("Choose")
        }
        private var localTime: String {
            let leg = model.draft.form.legs[index]
            let city = arrival ? leg.toCity : leg.fromCity
            return city.map { WizardStrings.text("Time in {{city}}", locale: locale, arguments: ["city": $0]) }
                ?? t("Local time")
        }
        private func t(_ key: String) -> String { WizardStrings.text(key, locale: locale) }

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlanUITokens.space2) {
                    caption
                    Spacer(minLength: PlanUITokens.space2)
                    pill
                }
                VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                    caption
                    pill
                }
            }
            .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
            .frame(minHeight: PlanUITokens.wizardFlightRowHeight)
            .sheet(isPresented: $showingPicker) {
                WizardDateTimeSheet(title: title, localTime: localTime, value: WizardDateTime.date(value) ?? Date()) {
                    picked in
                    model.setDateTime(WizardDateTime.string(picked), index: index, arrival: arrival)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }

        private var caption: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(t(arrival ? "Arrives" : "Departs")).font(Typography.wizardRow.font)
                Text(localTime).font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
            }.fixedSize(horizontal: false, vertical: true)
        }

        private var pill: some View {
            Button {
                showingPicker = true
            } label: {
                Text(displayedValue)
                    .font(Typography.wizardRow.font).monospacedDigit()
                    .foregroundStyle((value.isEmpty ? ColorToken.mutedForeground : .foreground).color)
                    .padding(.horizontal, PlanUITokens.space3).padding(.vertical, PlanUITokens.wizardControlGap)
                    .background(Color.wizardPickerFill, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusSm))
                    .overlay {
                        RoundedRectangle(cornerRadius: PlanUITokens.radiusSm)
                            .strokeBorder(ColorToken.destructive.color, lineWidth: AuthTokens.focusWidth)
                            .opacity(model.draft.fieldErrors[key] == nil ? 0 : 1).allowsHitTesting(false)
                    }
                    .frame(minHeight: AuthTokens.touch)
            }
            .buttonStyle(.plain).accessibilityIdentifier(identifier + ".date-time")
            .accessibilityLabel(title).accessibilityValue(displayedValue)
        }
    }

    struct WizardDateTimeSheet: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        let title: String
        let localTime: String
        let picked: (Date) -> Void
        @State private var value: Date

        init(title: String, localTime: String, value: Date, picked: @escaping (Date) -> Void) {
            self.title = title
            self.localTime = localTime
            self.picked = picked
            _value = State(initialValue: value)
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                        Text(localTime).font(Typography.wizardHint.font).foregroundStyle(
                            ColorToken.mutedForeground.color)
                        DatePicker(title, selection: $value, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical).labelsHidden()
                            .environment(\.calendar, WizardDateTime.calendar)
                            .environment(\.timeZone, WizardDateTime.calendar.timeZone)
                            .accessibilityIdentifier("wizard.native-picker")
                    }.padding(PlanUITokens.space5)
                }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(WizardStrings.text("Cancel", locale: locale)) { dismiss() }
                            .accessibilityIdentifier("wizard.picker.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(WizardStrings.text("Done", locale: locale)) {
                            picked(value)
                            dismiss()
                        }.accessibilityIdentifier("wizard.picker.done")
                    }
                }
            }
            .tint(ColorToken.primary.color)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .accessibilityIdentifier("wizard.date-time-sheet")
        }
    }
#endif

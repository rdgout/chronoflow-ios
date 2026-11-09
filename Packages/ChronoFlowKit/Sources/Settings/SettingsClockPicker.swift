#if canImport(UIKit)
    import AppCore
    import SwiftUI

    @MainActor struct SettingsClockPicker: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.locale) private var locale
        @State private var date: Date
        let title: String
        let save: (String) -> Void
        init(title: String, value: String?, save: @escaping (String) -> Void) {
            self.title = title
            self.save = save
            let parts = (value ?? "12:00").split(separator: ":").compactMap { Int($0) }
            _date = State(
                initialValue: Calendar.current.date(
                    from: DateComponents(year: 2001, month: 1, day: 1, hour: parts.first ?? 12, minute: parts.last ?? 0)
                ) ?? .now)
        }
        private func t(_ key: String) -> String {
            SettingsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }
        var body: some View {
            NavigationStack {
                DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden()
                    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("Done")) {
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                                save(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
                                dismiss()
                            }
                        }
                    }
            }.presentationDetents([.medium])
        }
    }
#endif

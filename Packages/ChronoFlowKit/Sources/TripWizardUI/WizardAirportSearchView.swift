#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    struct WizardAirportSearchView: View {
        @Environment(\.locale) private var locale
        let sheet: WizardAirportSheet
        let model: MemberWizardModel
        @State private var query = ""
        @State private var results: [ApiAirportSuggestion] = []
        @State private var selected = false

        private func t(_ key: String, arguments: [String: String] = [:]) -> String {
            WizardStrings.text(key, locale: locale, arguments: arguments)
        }

        private var title: String {
            switch sheet.side {
            case .from: t("Where do you fly from?")
            case .to: t("Where do you fly to?")
            case .home: t("Where do you fly home to?")
            case .stop: t("Where's your stop?")
            }
        }

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                    if sheet.side == .stop {
                        let leg = model.draft.form.legs[sheet.index]
                        Text(
                            t(
                                "Between {{from}} and {{to}}",
                                arguments: ["from": leg.fromCity ?? leg.fromIata, "to": leg.toCity ?? leg.toIata])
                        )
                        .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    WizardSearchField(text: $query, prompt: t("Search airports"))
                        .frame(height: PlanUITokens.wizardSwapSize)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.iata) { index, airport in
                                if index > 0 { Divider().overlay(ColorToken.border.color) }
                                result(airport)
                            }
                        }
                        .background(
                            ColorToken.background.color,
                            in: RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius).strokeBorder(
                                ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius))
                    }
                }
                .padding(.horizontal, PlanUITokens.space5).padding(.top, PlanUITokens.wizardContentGap)
                .background(ColorToken.card.color)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(t("Cancel")) { model.openAirport(nil) }.tint(ColorToken.dawnText.color)
                    }
                }
                .task(id: query) {
                    results = []
                    do {
                        let values = try await model.search.results(for: query)
                        guard !Task.isCancelled else { return }
                        results = values
                    } catch is CancellationError { return } catch { results = [] }
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.airport-search")
            }.presentationDetents([.large]).presentationDragIndicator(.visible)
                .presentationBackground(ColorToken.card.color).presentationCornerRadius(PlanUITokens.wizardSheetRadius)
        }

        private func result(_ airport: ApiAirportSuggestion) -> some View {
            Button {
                guard !selected else { return }
                selected = true
                if sheet.side == .stop {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                model.chooseAirport(airport, sheet: sheet)
            } label: {
                HStack(spacing: PlanUITokens.space3) {
                    WelcomeText(airport.iata, style: Typography.wizardSearchCode, color: .foreground)
                        .frame(width: PlanUITokens.wizardSearchCodeWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        WelcomeText(airport.name, style: Typography.wizardSearchName, color: .foreground)
                        Text(
                            [airport.city, locale.localizedString(forRegionCode: airport.country)]
                                .compactMap { $0 }.joined(separator: ", ")
                        )
                        .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, PlanUITokens.space4).padding(.vertical, PlanUITokens.space2)
                .frame(maxWidth: .infinity, minHeight: PlanUITokens.wizardSearchRowHeight, alignment: .leading)
                .contentShape(Rectangle()).foregroundStyle(ColorToken.foreground.color)
            }.buttonStyle(.plain).accessibilityIdentifier("wizard.airport.\(airport.iata)")
        }
    }

    private struct WizardSearchField: UIViewRepresentable {
        @Binding var text: String
        let prompt: String

        func makeUIView(context: Context) -> UISearchTextField {
            let search = UISearchTextField()
            search.autocapitalizationType = .none
            search.autocorrectionType = .no
            search.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
            search.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return search
        }

        func updateUIView(_ search: UISearchTextField, context: Context) {
            context.coordinator.parent = self
            if search.text != text { search.text = text }
            search.placeholder = prompt
            search.font = Typography.wizardRow.uiFont(compatibleWith: search.traitCollection)
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject {
            var parent: WizardSearchField
            init(_ parent: WizardSearchField) { self.parent = parent }
            @objc func changed(_ field: UISearchTextField) { parent.text = field.text ?? "" }
        }
    }
#endif

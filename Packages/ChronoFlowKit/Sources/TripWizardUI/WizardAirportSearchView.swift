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
                VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                    if sheet.side == .stop {
                        let leg = model.draft.form.legs[sheet.index]
                        Text(
                            t(
                                "Between {{from}} and {{to}}",
                                arguments: ["from": leg.fromCity ?? leg.fromIata, "to": leg.toCity ?? leg.toIata])
                        )
                        .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color).padding(
                            .horizontal, PlanUITokens.space5)
                    }
                    List(results, id: \.iata) { airport in
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
                                Text(airport.iata).font(Typography.screenLabel.font)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(airport.name).font(Typography.screenBodyLg.font)
                                    Text(
                                        [
                                            airport.city,
                                            Locale(identifier: locale.identifier).localizedString(
                                                forRegionCode: airport.country),
                                        ].compactMap { $0 }.joined(separator: ", ")
                                    )
                                    .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                                }
                            }.foregroundStyle(ColorToken.foreground.color)
                        }.accessibilityIdentifier("wizard.airport.\(airport.iata)")
                            .listRowBackground(ColorToken.card.color)
                    }.scrollContentBackground(.hidden)
                }
                .background(ColorToken.background.color)
                .searchable(
                    text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: t("Search airports")
                )
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("Cancel")) { model.openAirport(nil) } }
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
        }
    }
#endif

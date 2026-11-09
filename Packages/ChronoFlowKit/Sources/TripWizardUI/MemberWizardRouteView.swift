#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        func routeScreen(home: Bool = false) -> some View {
            let route = model.draft.form.route(home: home)
            let start = home ? model.draft.form.returnBoundary : 0
            let same = route.first?.iata.isEmpty == false && route.first?.iata == route.last?.iata
            return wizardShell(
                title: t(home ? "Your flight home" : "Where are you flying?"),
                subtitle: t(
                    home
                        ? "It leaves from where you landed. Add any stops on the way."
                        : "Pick the airports from your booking."),
                id: home ? "return-route" : "where", button: t("Continue"),
                enabled: model.draft.form.routeComplete(home: home),
                action: { if home { model.finishReturnRoute() } else { model.go(.outbound) } },
                content: {
                    routeCard(route, home: home)
                    if same {
                        errorLine(
                            t("From and To are the same airport. Choose where you land."),
                            identifier: "wizard.where.same")
                    }
                    ForEach(
                        model.draft.fieldErrors.keys.filter { key in
                            (start..<(start + max(0, route.count - 1))).contains { index in
                                key == "legs.\(index).fromIata" || key == "legs.\(index).toIata"
                            }
                        }.sorted(), id: \.self
                    ) { key in
                        errorLine(fieldCopy(model.draft.fieldErrors[key]!), identifier: "wizard.route.error.\(key)")
                    }
                    if model.draft.form.routeComplete(home: home) { routeStopQuestion(route, home: home) }
                })
        }

        private func routeCard(_ route: [WizardRouteAirport], home: Bool) -> some View {
            VStack(spacing: 0) {
                ForEach(Array(route.enumerated()), id: \.offset) { position, airport in
                    if position > 0 { Divider().overlay(ColorToken.border.color) }
                    routeRow(airport, position: position, route: route, home: home)
                }
            }
            .wizardCard()
            .overlay(alignment: .trailing) {
                if !home && route.count == 2 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        model.swapAirports()
                    } label: {
                        swapGlyph
                    }
                    .buttonStyle(.plain).tint(ColorToken.foreground.color)
                    .disabled(route.contains { $0.iata.isEmpty })
                    .opacity(route.contains { $0.iata.isEmpty } ? PlanUITokens.wizardEmptyOpacity : 1)
                    .accessibilityLabel(t("Swap airports")).accessibilityIdentifier("wizard.swap")
                    .padding(.trailing, PlanUITokens.wizardSwapInset)
                }
            }
        }

        private func routeRow(_ airport: WizardRouteAirport, position: Int, route: [WizardRouteAirport], home: Bool)
            -> some View
        {
            let start = home ? model.draft.form.returnBoundary : 0
            let isStop = position > 0 && position < route.count - 1
            let label =
                position == 0
                ? t("From")
                : isStop
                    ? (route.count == 3 ? t("Stop") : t("Stop {{number}}", ["number": String(position)])) : t("To")
            let index = start + max(0, position - 1)
            let field = position == 0 ? "legs.\(start).fromIata" : "legs.\(index).toIata"
            let same = position == route.count - 1 && !airport.iata.isEmpty && airport.iata == route.first?.iata
            return HStack(spacing: PlanUITokens.space2) {
                routeAirportRow(
                    label, airport: airport, locked: home && position == 0,
                    lastTrip: !home && position == 0 && model.draft.state.fromLastTrip,
                    reserveSwap: !home && route.count == 2,
                    invalid: same || model.draft.fieldErrors[field] != nil,
                    identifier: position == 0 ? "wizard.from" : isStop ? "wizard.stop.\(position)" : "wizard.to"
                ) {
                    model.openAirport(
                        WizardAirportSheet(
                            index: index, side: position == 0 ? .from : isStop ? .stop : home ? .home : .to,
                            replacingStop: isStop))
                }
                if isStop {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        model.removeStop(at: start + position)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: PlanUITokens.wizardStopGlyphSize))
                            .foregroundStyle(ColorToken.mutedForeground.color)
                            .frame(minWidth: AuthTokens.touch, minHeight: AuthTokens.touch)
                            .background(Color.wizardPickerFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("Remove stop in {{city}}", ["city": airport.city ?? airport.iata]))
                    .accessibilityIdentifier("wizard.remove-stop.\(position)")
                    .padding(.trailing, PlanUITokens.space3)
                }
            }
        }

        private func routeStopQuestion(_ route: [WizardRouteAirport], home: Bool) -> some View {
            let stops = max(0, route.count - 2)
            let canAdd = model.draft.form.legs.count < WizardForm.maxFlights
            let last = home ? model.draft.form.legs.count - 1 : model.draft.form.returnBoundary - 1
            return VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                VStack(alignment: .leading, spacing: PlanUITokens.wizardChoiceGap) {
                    Text(t("Do you change planes on the way?")).font(Typography.wizardRow.font)
                    Picker(
                        t("Do you change planes on the way?"),
                        selection: Binding(
                            get: { stops > 0 || model.draft.state.sheet?.side == .stop },
                            set: { hasStops in
                                if hasStops && stops == 0 && canAdd {
                                    model.openAirport(WizardAirportSheet(index: last, side: .stop))
                                } else if !hasStops {
                                    if stops > 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                                    model.makeDirect(home: home)
                                }
                            })
                    ) {
                        Text(t("No, direct")).tag(false)
                        Text(t("Yes")).tag(true).disabled(!canAdd && stops == 0)
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("wizard.route.stops")
                }
                if !canAdd {
                    Text(t("That's the most we can plan: 16 flights."))
                        .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                        .accessibilityIdentifier("wizard.route.limit")
                } else if stops > 0 {
                    Button {
                        model.openAirport(WizardAirportSheet(index: last, side: .stop))
                    } label: {
                        Label(t("Add another stop"), systemImage: "plus").font(Typography.wizardNavTitle.font)
                            .frame(minHeight: AuthTokens.touch)
                    }
                    .tint(ColorToken.dawnText.color).accessibilityIdentifier("wizard.add-stop")
                }
            }
        }

        private func routeAirportRow(
            _ label: String, airport: WizardRouteAirport, locked: Bool, lastTrip: Bool, reserveSwap: Bool,
            invalid: Bool, identifier: String, action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                        Text(label).font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                        Text(
                            airport.iata.isEmpty
                                ? t("Choose an airport")
                                : [airport.iata, airport.city].compactMap { $0 }.joined(separator: " · ")
                        )
                        .font(
                            (airport.iata.isEmpty ? Typography.wizardAirportPlaceholder : Typography.wizardAirport).font
                        )
                        .foregroundStyle((airport.iata.isEmpty ? ColorToken.mutedForeground : .foreground).color)
                        if locked || lastTrip {
                            Text(t(locked ? "Where you landed" : "From your last trip"))
                                .font(Typography.wizardHint.font)
                                .foregroundStyle((locked ? ColorToken.mutedForeground : .dawnText).color)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if locked { Image(systemName: "lock").foregroundStyle(ColorToken.mutedForeground.color) }
                }
                .frame(minHeight: PlanUITokens.wizardAirportHeight)
                .padding(.leading, PlanUITokens.space4)
                .padding(.trailing, reserveSwap ? PlanUITokens.space16 : PlanUITokens.space3)
                .padding(.vertical, PlanUITokens.space2)
                .overlay {
                    if invalid {
                        RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius)
                            .strokeBorder(ColorToken.destructive.color, lineWidth: AuthTokens.focusWidth)
                    }
                }
            }
            .buttonStyle(.plain).disabled(locked).accessibilityIdentifier(identifier)
            .accessibilityLabel(
                locked
                    ? t(
                        "Leaves from {{city}}, where you landed. You can't change this.",
                        ["city": airport.city ?? airport.iata])
                    : label + ", "
                        + (airport.iata.isEmpty ? t("Choose an airport") : airport.iata + " · " + (airport.city ?? "")))
        }

        @ViewBuilder private var swapGlyph: some View {
            let glyph = Image(systemName: "arrow.up.arrow.down")
                .frame(width: PlanUITokens.wizardSwapSize, height: PlanUITokens.wizardSwapSize)
            if #available(iOS 26, *) { glyph.glassEffect(.regular.interactive(), in: Circle()) } else { glyph }
        }
    }
#endif

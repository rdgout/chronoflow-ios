#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import PlanCore
    import TripWizard
    import UIKit

    public struct MemberWizardView: View {
        @Environment(\.locale) var locale
        @Bindable var model: MemberWizardModel
        let dismiss: () -> Void
        @State var path: [Destination]
        @State var confirmingDiscard = false
        @State var continuing = false
        @State var closing = false
        enum Destination: Hashable {
            case outbound, returnChoice, returnFlight, sleep, checking
            case question(Int)
            case excluded, continuation
        }
        @State var copyFormatter: CopyLineFormatter?

        public init(model: MemberWizardModel, dismiss: @escaping () -> Void) {
            self.model = model
            self.dismiss = dismiss
            _path = State(initialValue: Self.destinations(model))
        }

        func t(_ key: String, _ arguments: [String: String] = [:]) -> String {
            WizardStrings.text(key, locale: locale, arguments: arguments)
        }

        public var body: some View {
            NavigationStack(path: $path) {
                whereScreen.navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .outbound: outboundScreen
                    case .returnChoice: returnScreen
                    case .returnFlight: returnFlightScreen
                    case .sleep: sleepScreen
                    case .checking: checkingScreen
                    case .question(let index): questionScreen(index)
                    case .excluded: excludedScreen
                    case .continuation:
                        #if DEBUG
                            continuation
                        #else
                            ColorToken.background.color
                        #endif
                    }
                }
            }
            .tint(ColorToken.primary.color)
            .interactiveDismissDisabled()
            .task {
                if copyFormatter == nil { copyFormatter = try? await CopyLineFormatter(catalog: CopyCatalog.load()) }
                model.resumeChecking()
            }
            .onChange(of: model.draft.state.step) { _, _ in path = Self.destinations(model) }
            .onChange(of: model.draft.state.questionIndex) { _, _ in path = Self.destinations(model) }
            .onChange(of: path) { previous, next in
                continuing = false
                guard next.count < previous.count else { return }
                if case .question(let index) = next.last {
                    model.navigateToQuestion(index)
                } else if next != Self.destinations(model) {
                    model.go(Self.step(next.last))
                }
            }
            .sheet(item: Binding(get: { model.draft.state.sheet }, set: { model.openAirport($0) })) { sheet in
                WizardAirportSearchView(sheet: sheet, model: model)
            }
            .alert(t("Discard this trip?"), isPresented: $confirmingDiscard) {
                Button(t("Keep editing"), role: .cancel) {}
                Button(t("Discard"), role: .destructive) { close() }
            } message: {
                Text(t("What you entered is not saved."))
            }
        }

        private var whereScreen: some View {
            shell(title: "Where are you flying?", subtitle: "Pick the airports from your booking.", outbound: false) {
                let first = model.draft.form.legs[0]
                let last = model.draft.form.legs[model.draft.form.returnBoundary - 1]
                let same = !first.fromIata.isEmpty && first.fromIata == last.toIata
                VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                    VStack(spacing: 0) {
                        airportRow(
                            "From", iata: first.fromIata, city: first.fromCity, hint: model.draft.state.fromLastTrip
                        ) { model.openAirport(WizardAirportSheet(index: 0, side: .from)) }
                        Divider().overlay(ColorToken.border.color)
                        airportRow("To", iata: last.toIata, city: last.toCity, invalid: same) {
                            model.openAirport(WizardAirportSheet(index: model.draft.form.returnBoundary - 1, side: .to))
                        }
                    }
                    .wizardCard()
                    .overlay(alignment: .trailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.swapAirports()
                        } label: {
                            swapGlyph
                        }
                        .buttonStyle(.plain).tint(ColorToken.foreground.color)
                        .disabled(first.fromIata.isEmpty || last.toIata.isEmpty)
                        .opacity(first.fromIata.isEmpty || last.toIata.isEmpty ? PlanUITokens.wizardEmptyOpacity : 1)
                        .accessibilityLabel(t("Swap airports")).accessibilityIdentifier("wizard.swap")
                        .padding(.trailing, PlanUITokens.wizardSwapInset)
                    }
                    if same {
                        errorLine(
                            t("From and To are the same airport. Choose where you land."),
                            identifier: "wizard.where.same")
                    }
                }
            }
        }

        @ViewBuilder private var swapGlyph: some View {
            let glyph = Image(systemName: "arrow.up.arrow.down")
                .frame(width: PlanUITokens.wizardSwapSize, height: PlanUITokens.wizardSwapSize)
            if #available(iOS 26, *) {
                glyph.glassEffect(.regular.interactive(), in: Circle())
            } else {
                glyph
            }
        }

        func airportRow(
            _ label: String, iata: String, city: String?, hint: Bool = false, invalid: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                    Text(t(label)).font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                    Text(
                        iata.isEmpty ? t("Choose an airport") : [iata, city].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font((iata.isEmpty ? Typography.wizardAirportPlaceholder : Typography.wizardAirport).font)
                    .foregroundStyle(
                        (iata.isEmpty ? ColorToken.mutedForeground : .foreground).color)
                    if hint {
                        Text(t("From your last trip")).font(Typography.wizardHint.font).foregroundStyle(
                            ColorToken.dawnText.color)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: PlanUITokens.wizardAirportHeight, alignment: .leading)
                .padding(.leading, PlanUITokens.space4).padding(.trailing, PlanUITokens.space16)
                .overlay {
                    if invalid {
                        UnevenRoundedRectangle(
                            bottomLeadingRadius: PlanUITokens.wizardCardRadius,
                            bottomTrailingRadius: PlanUITokens.wizardCardRadius
                        ).strokeBorder(ColorToken.destructive.color, lineWidth: AuthTokens.focusWidth)
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier(label == "From" ? "wizard.from" : "wizard.to")
        }

        private var outboundScreen: some View {
            shell(title: "When is your flight?", subtitle: "Times are local at each airport.", outbound: true) {
                if let banner = model.draft.fieldErrors["review"] {
                    flightNotice(banner, identifier: "wizard.outbound.past")
                }
                ForEach(
                    Array(model.draft.form.legs.prefix(model.draft.form.returnBoundary).enumerated()), id: \.element.id
                ) { index, leg in
                    if index > 0 { connection(index) }
                    VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                        flightCard(index: index, leg: leg)
                    }
                }
                if model.draft.form.returnBoundary == 1 { flightDuration(index: 0) }
                if model.draft.form.legs.count < WizardForm.maxFlights {
                    Button {
                        model.openAirport(WizardAirportSheet(index: model.draft.form.returnBoundary - 1, side: .stop))
                    } label: {
                        Label(
                            t(model.draft.form.returnBoundary > 1 ? "Add another stop" : "Add a stop"),
                            systemImage: "plus"
                        )
                        .font(Typography.wizardNavTitle.font)
                        .padding(.horizontal, PlanUITokens.space1).frame(minHeight: AuthTokens.touch)
                    }.tint(ColorToken.dawnText.color).accessibilityIdentifier("wizard.add-stop")
                }
            }
        }

        func connection(_ index: Int) -> some View {
            HStack(spacing: PlanUITokens.space2) {
                dottedRule
                if let message = WizardOutboundRules.connection(
                    form: model.draft.form, index: index, airports: model.draft.airports,
                    duration: duration)
                {
                    HStack(spacing: PlanUITokens.space1) {
                        Text(
                            t(
                                message.key,
                                message.arguments.mapValues { value in
                                    if case .number(let number) = value {
                                        return NSDecimalNumber(decimal: number).stringValue
                                    }
                                    return value.string ?? ""
                                })
                        ).font(Typography.wizardHint.font).monospacedDigit()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.removeStop(at: index)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: PlanUITokens.wizardStopGlyphSize))
                                .foregroundStyle(ColorToken.mutedForeground.color)
                                .frame(
                                    width: PlanUITokens.wizardStopRemoveSize, height: PlanUITokens.wizardStopRemoveSize)
                        }
                        .accessibilityLabel(
                            t(
                                "Remove stop in {{city}}",
                                ["city": model.draft.form.legs[index].fromCity ?? model.draft.form.legs[index].fromIata]
                            )
                        )
                        .accessibilityIdentifier("wizard.remove-stop.\(index)")
                    }.padding(.leading, PlanUITokens.space3).padding(.trailing, PlanUITokens.space1)
                        .padding(.vertical, PlanUITokens.wizardLabelGap)
                        .background(ColorToken.surface2.color, in: Capsule())
                }
                dottedRule
            }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .contain)
                .accessibilityIdentifier("wizard.connection.\(index)")
        }

        private var dottedRule: some View {
            Color.clear.frame(height: AuthTokens.focusWidth).overlay {
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                    }.stroke(
                        ColorToken.border.color,
                        style: StrokeStyle(
                            lineWidth: AuthTokens.focusWidth, lineCap: .round,
                            dash: [PlanUITokens.wizardStopDotWidth, PlanUITokens.wizardStopDotGap]))
                }
            }.accessibilityHidden(true)
        }

        func flightNotice(_ message: FieldMessage, identifier: String) -> some View {
            HStack(alignment: .top, spacing: PlanUITokens.wizardNoticeGap) {
                Image(systemName: "info.circle").font(.system(size: PlanUITokens.wizardNoticeIconSize))
                    .accessibilityHidden(true)
                Text(fieldCopy(message)).font(Typography.screenBody.font)
            }
            .padding(.horizontal, PlanUITokens.wizardContentGap).padding(.vertical, PlanUITokens.space3)
            .background(ColorToken.authErrorBackground.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusXl))
            .overlay {
                RoundedRectangle(cornerRadius: PlanUITokens.radiusXl).strokeBorder(
                    ColorToken.authErrorBorder.color, lineWidth: AuthTokens.borderWidth)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
        }

        func flightCard(index: Int, leg: WizardLeg) -> some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                Label {
                    Text(leg.fromIata + " → " + leg.toIata).foregroundStyle(ColorToken.foreground.color)
                } icon: {
                    Image(systemName: "airplane.departure").foregroundStyle(ColorToken.dawnText.color)
                }.font(Typography.wizardRoute.font).padding(.horizontal, PlanUITokens.space1)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    WizardFlightDateTimeRow(model: model, index: index, arrival: false)
                    Divider().overlay(ColorToken.border.color)
                    WizardFlightDateTimeRow(model: model, index: index, arrival: true)
                }.wizardCard()
                ForEach(["departLocal", "arriveLocal"], id: \.self) { field in
                    if let error = model.draft.fieldErrors["legs.\(index).\(field)"] {
                        errorLine(
                            fieldCopy(error),
                            identifier: "wizard.\(index)." + (field == "arriveLocal" ? "arrival" : "departure")
                                + ".error")
                    }
                }
            }
        }

        @ViewBuilder func flightDuration(index: Int) -> some View {
            if let minutes = WizardOutboundRules.flightMinutes(
                form: model.draft.form, index: index, airports: model.draft.airports)
            {
                Text(t("Flight time {{d}}", ["d": duration(minutes)]))
                    .font(Typography.wizardHint.font).monospacedDigit().foregroundStyle(
                        ColorToken.mutedForeground.color)
            }
        }

        func duration(_ minutes: Int) -> String {
            t(
                "{{hours}} h {{minutes}} min",
                ["hours": String(minutes / 60), "minutes": String(minutes % 60)])
        }

        private func shell<Content: View>(
            title: String, subtitle: String, outbound: Bool, @ViewBuilder content: () -> Content
        ) -> some View {
            wizardShell(
                title: t(title), subtitle: t(subtitle), id: outbound ? "outbound" : "where",
                button: t("Continue"), enabled: outbound ? model.outboundComplete : model.whereComplete,
                action: {
                    if outbound {
                        if model.finishOutbound() {
                            model.go(.returnChoice)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    } else {
                        model.go(.outbound)
                    }
                }, content: content)
        }

        #if DEBUG
            private var continuation: some View {
                VStack(spacing: PlanUITokens.space4) {
                    Text(t("The next wizard steps are being built in Phase 16c."))
                    Text(t("Continue · Phase 16c (temporary)"))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ColorToken.background.color)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.debug.continue")
            }
        #endif

        func close() {
            guard !closing else { return }
            closing = true
            Task {
                do {
                    try await model.discard()
                    dismiss()
                } catch {
                    closing = false
                    assertionFailure("Wizard recovery discard failed: \(error)")
                }
            }
        }
    }

    func errorLine(_ text: String, identifier: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(Typography.screenBody.font)
            .foregroundStyle(ColorToken.destructive.color).accessibilityIdentifier(identifier)
    }

    extension View {
        func wizardCard() -> some View {
            background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.wizardCardRadius).strokeBorder(
                        ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
        }
    }

#endif

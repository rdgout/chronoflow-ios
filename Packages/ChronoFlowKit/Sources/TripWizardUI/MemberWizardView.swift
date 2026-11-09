#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import PlanCore
    import TripWizard
    import UIKit

    public struct MemberWizardView: View {
        @Environment(\.locale) var locale
        @Environment(\.colorScheme) var scheme
        @Bindable var model: MemberWizardModel
        let dismiss: () -> Void
        @State var confirmingDiscard = false
        @State var continuing = false
        @State var closing = false
        @State var errorScrollRequest = 0
        typealias Destination = MemberWizardDestination
        @State var copyFormatter: CopyLineFormatter?

        public init(model: MemberWizardModel, dismiss: @escaping () -> Void) {
            self.model = model
            self.dismiss = dismiss
        }

        func t(_ key: String, _ arguments: [String: String] = [:]) -> String {
            WizardStrings.text(key, locale: locale, arguments: arguments)
        }

        public var body: some View {
            let presented = model.navigationPath
            NavigationStack(
                path: Binding(
                    get: { model.navigationPath },
                    set: {
                        continuing = false
                        model.popNavigation(to: $0, from: presented)
                    })
            ) {
                whereScreen.navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .outbound: outboundScreen
                    case .returnChoice: returnScreen
                    case .returnRoute: routeScreen(home: true)
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
            .onChange(of: model.navigationPath) { _, _ in continuing = false }
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

        private var whereScreen: some View { routeScreen() }

        private var outboundScreen: some View { timesScreen() }

        func timesScreen(home: Bool = false) -> some View {
            let start = home ? model.draft.form.returnBoundary : 0
            let end = home ? model.draft.form.legs.count : model.draft.form.returnBoundary
            return wizardShell(
                title: t(
                    home ? "When do you fly home?" : end - start > 1 ? "When are your flights?" : "When is your flight?"
                ),
                subtitle: t("Times are local at each airport."), id: home ? "return-flight" : "outbound",
                button: t("Continue"), enabled: home ? model.returnComplete : model.outboundComplete,
                action: {
                    if home ? model.finishReturn() : model.finishOutbound() {
                        if home { model.finishFlightInput() } else { model.go(.returnChoice) }
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                },
                content: {
                    if let banner = model.draft.fieldErrors["review"] {
                        flightNotice(banner, identifier: home ? "wizard.return-flight.past" : "wizard.outbound.past")
                    }
                    ForEach(
                        Array(model.draft.form.legs.enumerated()).filter { (start..<end).contains($0.offset) },
                        id: \.element.id
                    ) { index, leg in
                        if index > start { connection(index) }
                        flightCard(index: index, leg: leg).id("wizard.flight.\(index)")
                            .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.flight.\(index)")
                    }
                    if end - start == 1 { flightDuration(index: start) }
                })
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
                    }.padding(.horizontal, PlanUITokens.space3)
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
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
        }
        .font(Typography.screenBody.font).foregroundStyle(ColorToken.destructive.color)
        .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
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

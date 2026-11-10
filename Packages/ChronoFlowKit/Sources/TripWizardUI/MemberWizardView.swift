#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import PlanCore
    import TripWizard
    import UIKit

    public struct MemberWizardView: View {
        @Environment(\.dynamicTypeSize) var dynamicTypeSize
        @Environment(\.scenePhase) var scenePhase
        @Environment(\.locale) var locale
        @Environment(\.colorScheme) var scheme
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        @Environment(\.planContentMeasure) var planContentMeasure
        @Bindable var model: MemberWizardModel
        let dismiss: () -> Void
        let saved: (String) -> Void
        @State var confirmingDiscard = false
        @State var continuing = false
        @State var closing = false
        @State var errorScrollRequest = 0
        #if DEBUG
            @Environment(\.displayScale) var displayScale
            @State var initialScrollSeedReady = false
            var errorScrollOverride: Int?
        #endif
        typealias Destination = MemberWizardDestination
        @State var copyFormatter: CopyLineFormatter?

        public init(
            model: MemberWizardModel, saved: @escaping (String) -> Void = { _ in }, dismiss: @escaping () -> Void
        ) {
            self.model = model
            self.dismiss = dismiss
            self.saved = saved
        }

        var requestedErrorScroll: Int {
            #if DEBUG
                if let errorScrollOverride { return errorScrollOverride }
            #endif
            return errorScrollRequest
        }

        var errorScrollAnimation: Animation? {
            #if DEBUG
                if errorScrollOverride != nil { return nil }
            #endif
            return reduceMotion ? nil : .default
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
                whereScreen.environment(\.planContentMeasure, presented.isEmpty ? planContentMeasure : nil)
                    .navigationDestination(for: Destination.self) { destination in
                        Group {
                            switch destination {
                            case .outbound: outboundScreen
                            case .returnChoice: returnScreen
                            case .returnRoute: routeScreen(home: true)
                            case .returnFlight: returnFlightScreen
                            case .sleep: sleepScreen
                            case .checking: checkingScreen
                            case .question(let index): questionScreen(index)
                            case .excluded: excludedScreen
                            case .continuation, .fineTune: fineTuneScreen
                            case .ready: readyScreen
                            case .calculating: calculatingScreen
                            }
                        }
                        .environment(\.planContentMeasure, destination == presented.last ? planContentMeasure : nil)
                    }
            }
            .tint(ColorToken.primary.color)
            .interactiveDismissDisabled()
            .task {
                if copyFormatter == nil { copyFormatter = try? await CopyLineFormatter(catalog: CopyCatalog.load()) }
                model.resumeChecking()
                model.resumeCompletion()
            }
            .onChange(of: model.createdTripID) { _, id in
                if let id {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    saved(id)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.draft.state.promptSheetID != nil }, set: { if !$0 { model.openPrompt(nil) } })
            ) {
                if let prompt = model.optionalPrompts.first(where: { $0.id == model.draft.state.promptSheetID }) {
                    WizardAnswerSheet(
                        model: model, prompt: prompt, question: serverCopy(prompt.text), title: optionalLabel(prompt),
                        fieldCopy: fieldCopy)
                }
            }
            .onChange(of: model.navigationPath) { _, _ in continuing = false }
            .sheet(item: Binding(get: { model.draft.state.sheet }, set: { model.openAirport($0) })) { sheet in
                WizardAirportSearchView(sheet: sheet, model: model)
            }
            .alert(t("Discard this trip?"), isPresented: $confirmingDiscard) {
                Button(t("Keep editing"), role: .cancel) {}
                Button(t("Discard"), role: .destructive) { close() }
            } message: {
                Text(
                    t(
                        model.mode == .guest
                            ? "What you entered is not saved. You go back to the welcome screen."
                            : "What you entered is not saved."))
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
                        if home || model.draft.state.revisit != nil {
                            model.finishFlightInput()
                        } else {
                            model.finishOutboundStep()
                        }
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
                        Group {
                            if index == end - 1 {
                                flightCard(index: index, leg: leg).planContentBounds(
                                    identifier: "wizard.flight.\(index)")
                            } else {
                                flightCard(index: index, leg: leg)
                            }
                        }.id("wizard.flight.\(index)")
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
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(identifier)
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
                if ["departLocal", "arriveLocal"].contains(where: {
                    model.draft.fieldErrors["legs.\(index).\($0)"] != nil
                }) {
                    VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                        ForEach(["departLocal", "arriveLocal"], id: \.self) { field in
                            if let error = model.draft.fieldErrors["legs.\(index).\(field)"] {
                                errorLine(
                                    fieldCopy(error),
                                    identifier: "wizard.\(index)." + (field == "arriveLocal" ? "arrival" : "departure")
                                        + ".error")
                            }
                        }
                    }
                    .id("wizard.flight.errors.\(index)")
                    .planContentBounds(identifier: "wizard.flight.errors.\(index)")
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
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier(identifier)
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

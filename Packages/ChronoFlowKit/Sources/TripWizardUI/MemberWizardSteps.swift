#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        static func destinations(_ model: MemberWizardModel) -> [Destination] {
            let step = model.draft.state.step
            if step == .whereTo { return [] }
            if step == .outbound { return [.outbound] }
            var result: [Destination] = [.outbound, .returnChoice]
            if step == .returnChoice { return result }
            if model.draft.form.end.kind == "return_legs" { result.append(.returnFlight) }
            if step == .returnFlight { return result }
            if model.draft.state.sleepNeeded || model.draft.state.lastInputStep == .sleep || step == .sleep {
                result.append(.sleep)
            }
            switch step {
            case .checking: result.append(.checking)
            case .question:
                for index in 0...(model.draft.state.questionIndex ?? 0) { result.append(.question(index)) }
            case .excluded: result.append(.excluded)
            case .continuation: result.append(.continuation)
            default: break
            }
            return result
        }

        static func step(_ destination: Destination?) -> MemberWizardStep {
            switch destination {
            case nil: .whereTo
            case .outbound: .outbound
            case .returnChoice: .returnChoice
            case .returnFlight: .returnFlight
            case .sleep: .sleep
            case .checking: .checking
            case .question: .question
            case .excluded: .excluded
            case .continuation: .continuation
            }
        }

        func wizardShell<Content: View>(
            title: String, subtitle: String? = nil, id: String, button: String? = nil,
            enabled: Bool = true, action: @escaping () -> Void = {}, @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Capsule().fill(ColorToken.muted.color)
                        .overlay(alignment: .leading) {
                            Capsule().fill(ColorToken.dawn.color).frame(width: geometry.size.width * model.progress)
                        }
                }.frame(height: PlanUITokens.wizardProgressHeight)
                    .padding(.horizontal, PlanUITokens.space5)
                    .accessibilityLabel(t("Progress, {{pct}} percent", ["pct": String(Int(model.progress * 100))]))
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                        VStack(alignment: .leading, spacing: PlanUITokens.wizardControlGap) {
                            Text(title).font(
                                (title.count > 80 ? Typography.wizardLongTitle : Typography.screenPageTitle).font
                            )
                            .accessibilityAddTraits(.isHeader)
                            if let subtitle {
                                Text(subtitle).font(Typography.wizardSubtitle.font).foregroundStyle(
                                    ColorToken.mutedForeground.color)
                            }
                        }
                        content()
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(PlanUITokens.space5)
                }
            }
            .background(ColorToken.background.color).foregroundStyle(ColorToken.foreground.color)
            .safeAreaInset(edge: .bottom) {
                if let button {
                    VStack(spacing: PlanUITokens.space2) {
                        Button {
                            guard !continuing, !closing, enabled else { return }
                            continuing = true
                            action()
                            continuing = false
                        } label: {
                            Text(button).font(Typography.wizardButton.font)
                                .frame(maxWidth: .infinity, minHeight: PlanUITokens.wizardButtonHeight)
                        }
                        .buttonStyle(.plain).foregroundStyle(ColorToken.primaryForeground.color)
                        .background(ColorToken.primary.color, in: Capsule())
                        .disabled(!enabled || closing || continuing || model.persistenceFailed)
                        .opacity(enabled ? 1 : PlanUITokens.wizardDisabledOpacity)
                        .accessibilityIdentifier("wizard.\(id).continue")
                        if id == "excluded" || (id == "checking" && model.checking.failure != nil) {
                            Button(t("Close")) { close() }.frame(minHeight: AuthTokens.touch)
                        }
                    }.padding(.horizontal, PlanUITokens.space5).padding(.vertical, PlanUITokens.space3)
                        .background(ColorToken.background.color)
                }
            }
            .navigationTitle(t("New trip")).navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .navigationBarBackButtonHidden(id == "checking")
            .background { if id == "checking" { WizardSwipeBack() } }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("New trip")).font(Typography.wizardNavTitle.font)
                        .foregroundStyle(ColorToken.mutedForeground.color)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if model.draft.state.entered { confirmingDiscard = true } else { close() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(t("Close")).accessibilityIdentifier("wizard.close").disabled(closing)
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.\(id)")
        }

        var returnScreen: some View {
            wizardShell(title: t("Coming back?"), id: "return") {
                choice(
                    "One way", hint: "Just this flight", selected: model.draft.form.end.kind == "one_way", id: "one-way"
                ) {
                    model.chooseReturn("one_way")
                }
                choice(
                    "Add my return flight", hint: "We plan the shift back home too",
                    selected: model.draft.form.end.kind == "return_legs", id: "add-return",
                    enabled: model.draft.form.end.kind == "return_legs"
                        || model.draft.form.legs.count < WizardForm.maxFlights
                ) {
                    model.chooseReturn("return_legs")
                }
                if ["nights", "check_out"].contains(model.draft.form.end.kind) {
                    let title =
                        model.draft.form.end.kind == "nights"
                        ? t("Ends after {{count}} nights", ["count": String(model.draft.form.end.nights ?? 0)])
                        : WizardPresentation.returnSummary(
                            model.draft.form, stayEnd: model.draft.state.review?.summary?.stayEnd, locale: locale, t: t)
                    choice(
                        title, hint: "Set on the website. Keep it, or add your flight home.", selected: true, id: "web"
                    ) {
                        model.chooseReturn(model.draft.form.end.kind)
                    }
                }
                tapHint
            }
        }

        var returnFlightScreen: some View {
            wizardShell(
                title: t("Your flight home"), subtitle: t("It leaves from where you landed. Add your date and times."),
                id: "return-flight",
                button: t("Continue"), enabled: model.returnComplete,
                action: {
                    if model.finishReturn() {
                        model.finishFlightInput()
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                },
                content: {
                    if let banner = model.draft.fieldErrors["review"] {
                        Text(fieldCopy(banner)).font(Typography.screenBody.font).padding(PlanUITokens.space3)
                            .background(
                                ColorToken.authErrorBackground.color,
                                in: RoundedRectangle(cornerRadius: PlanUITokens.radiusXl)
                            )
                            .accessibilityIdentifier("wizard.return-flight.past")
                    }
                    if model.draft.form.legs.indices.contains(model.draft.form.returnBoundary) {
                        let first = model.draft.form.legs[model.draft.form.returnBoundary]
                        VStack(spacing: 0) {
                            HStack(spacing: PlanUITokens.space2) {
                                Image(systemName: "lock").accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                                    Text(t("From")).font(Typography.wizardHint.font)
                                    Text([first.fromIata, first.fromCity].compactMap { $0 }.joined(separator: " · "))
                                        .font(
                                            Typography.wizardAirport.font)
                                    Text(t("Where you landed")).font(Typography.wizardHint.font).foregroundStyle(
                                        ColorToken.mutedForeground.color)
                                }
                                Spacer(minLength: 0)
                            }.padding(PlanUITokens.space4)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(
                                    t(
                                        "Leaves from {{city}}, where you landed. You can't change this.",
                                        ["city": first.fromCity ?? first.fromIata])
                                )
                                .accessibilityIdentifier("wizard.return-flight.from")
                            Divider().overlay(ColorToken.border.color)
                            let last = model.draft.form.legs.last!
                            airportRow("To", iata: last.toIata, city: last.toCity) {
                                model.openAirport(
                                    WizardAirportSheet(index: model.draft.form.legs.count - 1, side: .home))
                            }
                        }.wizardCard()
                        ForEach(
                            Array(model.draft.form.legs.enumerated()).filter {
                                $0.offset >= model.draft.form.returnBoundary
                            }, id: \.element.id
                        ) { index, leg in
                            if index > model.draft.form.returnBoundary { connection(index) }
                            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                                Label(leg.fromIata + " → " + leg.toIata, systemImage: "airplane")
                                    .font(Typography.wizardRoute.font).foregroundStyle(ColorToken.dawnText.color)
                                VStack(spacing: 0) {
                                    WizardFlightDateTimeRow(model: model, index: index, arrival: false)
                                    Divider().overlay(ColorToken.border.color)
                                    WizardFlightDateTimeRow(model: model, index: index, arrival: true)
                                }.wizardCard()
                            }
                        }
                        if model.draft.form.legs.count < WizardForm.maxFlights {
                            Button {
                                model.openAirport(
                                    WizardAirportSheet(index: model.draft.form.legs.count - 1, side: .stop))
                            } label: {
                                Label(t("Add a stop"), systemImage: "plus").frame(minHeight: AuthTokens.touch)
                            }
                            .accessibilityIdentifier("wizard.return-flight.add-stop")
                        }
                    }
                })
        }

        var sleepScreen: some View {
            wizardShell(
                title: t("How do you usually sleep?"), subtitle: t("On a work day. We save it for next time."),
                id: "sleep",
                button: t("Continue"), enabled: model.sleepComplete,
                action: {
                    if !model.finishSleep() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                },
                content: {
                    VStack(spacing: 0) {
                        sleepTime("Usual bedtime", field: "habitual_bed")
                        Divider().overlay(ColorToken.border.color)
                        sleepTime("Usual wake-up", field: "habitual_wake")
                    }.wizardCard()
                    Text(t("When do you naturally feel most awake?")).font(Typography.wizardButton.font)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PlanUITokens.space2) {
                        ForEach(["early", "intermediate", "late", "unsure"], id: \.self) { key in
                            let labels = [
                                "early": ("Early bird", "Up early, tired in the evening"),
                                "intermediate": ("In between", "A normal working day"),
                                "late": ("Night owl", "Late nights, slow mornings"),
                                "unsure": ("Not sure", "We use your sleep times"),
                            ]
                            let value: JSONValue = key == "unsure" ? .null : .string(key)
                            choice(
                                labels[key]!.0, hint: labels[key]!.1,
                                selected: model.draft.state.profile["chronotype"] == value, id: "sleep.\(key)"
                            ) {
                                model.setSleep("chronotype", value: value)
                            }
                        }
                    }
                    ForEach(model.draft.fieldErrors.keys.filter { $0.hasPrefix("profile.") }.sorted(), id: \.self) {
                        key in
                        errorLine(fieldCopy(model.draft.fieldErrors[key]!), identifier: "wizard.sleep.error.\(key)")
                    }
                })
        }

        func sleepTime(_ label: String, field: String) -> some View {
            HStack(spacing: PlanUITokens.space2) {
                Text(t(label)).font(Typography.wizardRow.font)
                Spacer(minLength: 0)
                DatePicker(
                    t(label),
                    selection: Binding(
                        get: {
                            WizardDateTime.date("2000-01-01T" + (model.draft.state.profile[field]?.string ?? "12:00"))!
                        },
                        set: { value in
                            UISelectionFeedbackGenerator().selectionChanged()
                            model.setSleep(field, value: .string(String(WizardDateTime.string(value).suffix(5))))
                        }), displayedComponents: .hourAndMinute
                )
                .labelsHidden().environment(\.calendar, WizardDateTime.calendar).environment(
                    \.timeZone, WizardDateTime.calendar.timeZone
                )
                .accessibilityIdentifier("wizard.sleep.\(field)")
            }.padding(PlanUITokens.space4)
        }

        func choice(
            _ label: String, hint: String? = nil, selected: Bool, id: String, enabled: Bool = true,
            action: @escaping () -> Void
        ) -> some View {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                action()
            } label: {
                HStack(spacing: PlanUITokens.space3) {
                    VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                        Text(t(label)).font(Typography.wizardChoice.font)
                        if let hint {
                            Text(t(hint)).font(Typography.wizardHint.font).foregroundStyle(
                                ColorToken.mutedForeground.color)
                        }
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").foregroundStyle(ColorToken.dawnText.color) }
                }.frame(
                    maxWidth: .infinity,
                    minHeight: id.hasPrefix("question.") ? PlanUITokens.wizardFlightRowHeight : AuthTokens.touch,
                    alignment: .leading
                ).padding(
                    PlanUITokens.space4
                )
                .background(
                    ColorToken.card.color,
                    in: RoundedRectangle(
                        cornerRadius: (id.hasPrefix("sleep.")
                            ? PlanUITokens.radiusXl
                            : id.hasPrefix("question.") ? PlanUITokens.wizardQuestionRadius : PlanUITokens.radius2Xl))
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: (id.hasPrefix("sleep.")
                            ? PlanUITokens.radiusXl
                            : id.hasPrefix("question.") ? PlanUITokens.wizardQuestionRadius : PlanUITokens.radius2Xl)
                    ).strokeBorder(
                        (selected ? ColorToken.dawn : .border).color, lineWidth: AuthTokens.focusWidth)
                }
            }.buttonStyle(.plain).disabled(!enabled || model.choicePending).accessibilityIdentifier(
                "wizard.choice.\(id)"
            )
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }

        var tapHint: some View {
            Text(t("Tap an answer to continue.")).font(Typography.wizardHint.font).foregroundStyle(
                ColorToken.mutedForeground.color)
        }

        func serverCopy(_ line: CopyLine) -> String {
            copyFormatter?.format(
                line, options: CopyFormat(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)) ?? ""
        }
        func fieldCopy(_ message: FieldMessage) -> String {
            let arguments = message.arguments.mapValues { value in
                if case .number(let number) = value { return NSDecimalNumber(decimal: number).stringValue }
                return value.string ?? ""
            }
            if let catalog = copyFormatter?.catalog, catalog.contains(message.key) {
                return catalog.text(
                    message.key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                    arguments: arguments)
            }
            return t(message.key, arguments)
        }
    }
#endif

#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        func wizardShell<Content: View>(
            title: String, subtitle: String? = nil, eyebrow: String? = nil, id: String, button: String? = nil,
            answerHint: Bool = false,
            enabled: Bool = true, action: @escaping () -> Void = {}, @ViewBuilder content: @escaping () -> Content
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
                ScrollViewReader { proxy in
                    ScrollView {
                        initialScrollSeedContent(id: id) {
                            VStack(alignment: .leading, spacing: PlanUITokens.wizardContentGap) {
                                VStack(alignment: .leading, spacing: PlanUITokens.wizardControlGap) {
                                    if let eyebrow {
                                        Text(eyebrow.uppercased()).font(Typography.screenEyebrow.font)
                                            .tracking(Typography.screenEyebrow.tracking).foregroundStyle(
                                                ColorToken.dawnText.color)
                                    }
                                    WelcomeText(
                                        title,
                                        style: title.count > 80
                                            ? Typography.wizardLongTitle : Typography.screenPageTitle,
                                        color: .foreground
                                    )
                                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("wizard.title")
                                    if let subtitle {
                                        Text(subtitle).font(Typography.wizardSubtitle.font).foregroundStyle(
                                            ColorToken.mutedForeground.color)
                                    }
                                }
                                content()
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(PlanUITokens.space5)
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let button {
                            VStack(spacing: PlanUITokens.wizardControlGap) {
                                if id == "excluded" || (id == "checking" && model.checking.failure != nil) {
                                    Button(t("Close")) {
                                        if id == "excluded" { close() } else { confirmingDiscard = true }
                                    }
                                    .buttonStyle(.plain).font(Typography.wizardSecondary.font)
                                    .foregroundStyle(ColorToken.foreground.color).frame(minHeight: AuthTokens.touch)
                                    .disabled(closing).accessibilityIdentifier("wizard.\(id).secondary-close")
                                }
                                Button {
                                    guard !continuing, !closing, enabled else { return }
                                    continuing = true
                                    action()
                                    if id == "outbound" || id == "return-flight" { errorScrollRequest += 1 }
                                    continuing = false
                                } label: {
                                    HStack(spacing: PlanUITokens.space2) {
                                        if model.reviewing { ProgressView().tint(ColorToken.primaryForeground.color) }
                                        Text(button)
                                    }.font(Typography.wizardButton.font)
                                        .frame(maxWidth: .infinity, minHeight: PlanUITokens.wizardButtonHeight)
                                }
                                .buttonStyle(.plain).foregroundStyle(
                                    (id == "excluded" ? ColorToken.foreground : .primaryForeground).color
                                )
                                .background((id == "excluded" ? ColorToken.surface2 : .primary).color, in: Capsule())
                                .disabled(
                                    !enabled || closing || continuing || model.persistenceFailed || model.reviewing
                                )
                                .opacity(enabled ? 1 : PlanUITokens.wizardDisabledOpacity)
                                .accessibilityIdentifier("wizard.\(id).continue")
                            }.padding(.horizontal, PlanUITokens.space5).padding(.vertical, PlanUITokens.space3)
                                .background(ColorToken.background.color)
                                .accessibilityElement(children: .contain).accessibilityIdentifier(
                                    footerIdentifier(for: id)
                                )
                                .planContentBounds(identifier: "wizard.\(id).footer")
                        } else if id == "ready", model.credits == .unavailable {
                            VStack(spacing: 0) {
                                Button {
                                    confirmingDiscard = true
                                } label: {
                                    Text(t("Close")).frame(maxWidth: .infinity, minHeight: AuthTokens.touch)
                                }
                                .buttonStyle(.plain).font(Typography.wizardSecondary.font)
                                .disabled(closing).accessibilityIdentifier("wizard.ready.no-credits")
                                .planContentBounds(identifier: "wizard.ready.no-credits")
                            }.padding(.horizontal, PlanUITokens.space5).padding(.vertical, PlanUITokens.space3)
                                .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.ready.footer")
                                .planContentBounds(identifier: "wizard.ready.footer")
                                .background(ColorToken.background.color)
                        } else if answerHint {
                            tapHint.frame(maxWidth: .infinity).multilineTextAlignment(.center)
                                .padding(.horizontal, PlanUITokens.space5).padding(
                                    .bottom, PlanUITokens.wizardHintBottom
                                )
                                .background(ColorToken.background.color)
                        }
                    }
                    .defaultScrollAnchor(initialScrollAnchor(for: id))
                    .onChange(of: requestedErrorScroll) { _, _ in
                        let start = id == "return-flight" ? model.draft.form.returnBoundary : 0
                        let end = id == "return-flight" ? model.draft.form.legs.count : model.draft.form.returnBoundary
                        if let index = (start..<end).first(where: { index in
                            model.draft.fieldErrors.keys.contains { $0.hasPrefix("legs.\(index).") }
                        }) {
                            // Newly inserted errors need their scroll anchors committed first.
                            DispatchQueue.main.async {
                                withAnimation(errorScrollAnimation) {
                                    proxy.scrollTo("wizard.flight.errors.\(index)", anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: PlanUITokens.wizardColumnWidth).frame(maxWidth: .infinity)
            .background(ColorToken.background.color).foregroundStyle(ColorToken.foreground.color)
            .navigationTitle(t("New trip")).navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .navigationBarBackButtonHidden(id == "calculating" || (id == "checking" && model.checking.failure == nil))
            .background { if id == "checking" { WizardSwipeBack() } }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("New trip")).font(Typography.wizardNavTitle.font)
                        .foregroundStyle(ColorToken.mutedForeground.color)
                }
                if id != "calculating" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if model.draft.state.entered { confirmingDiscard = true } else { close() }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(t("Close")).accessibilityIdentifier("wizard.close").disabled(closing)
                    }
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.\(id)")
        }

        private func initialScrollAnchor(for id: String) -> UnitPoint? {
            #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if id == "outbound", environment["CF_WIZARD_BOARD_CAPTURE"] == "WizardOutboundScrollErrors",
                    UUID(uuidString: environment["CF_AUTH_TEST_ID"] ?? "") != nil
                {
                    return .bottom
                }
            #endif
            return nil
        }

        @ViewBuilder private func initialScrollSeedContent<Content: View>(
            id: String, @ViewBuilder content: () -> Content
        ) -> some View {
            #if DEBUG
                if initialScrollAnchor(for: id) != nil {
                    content().onGeometryChange(for: Bool.self) { geometry in
                        guard let viewport = geometry.bounds(of: .scrollView), !viewport.isEmpty,
                            geometry.size.height > 0
                        else { return false }
                        return geometry.size.height > viewport.minY
                            && geometry.size.height <= viewport.maxY + 1 / displayScale
                    } action: { atBottom in
                        if atBottom { initialScrollSeedReady = true }
                    }
                } else {
                    content()
                }
            #else
                content()
            #endif
        }

        private func footerIdentifier(for id: String) -> String {
            #if DEBUG
                if initialScrollAnchor(for: id) != nil && !initialScrollSeedReady { return "" }
            #endif
            return "wizard.\(id).footer"
        }

        var returnScreen: some View {
            wizardShell(title: t("Coming back?"), id: "return", answerHint: true) {
                VStack(spacing: PlanUITokens.wizardChoiceGap) {
                    if ["nights", "check_out"].contains(model.draft.form.end.kind) {
                        let title =
                            model.draft.form.end.kind == "nights"
                            ? t("Ends after {{count}} nights", ["count": String(model.draft.form.end.nights ?? 0)])
                            : WizardPresentation.returnSummary(
                                model.draft.form, stayEnd: model.draft.state.review?.summary?.stayEnd, locale: locale,
                                t: t)
                        choice(
                            title, hint: "Set on the website. Keep it, or add your flight home.", selected: true,
                            id: "web"
                        ) {
                            model.chooseReturn(model.draft.form.end.kind)
                        }
                    }
                    choice(
                        "One way", hint: "Just this flight", selected: model.draft.form.end.kind == "one_way",
                        id: "one-way"
                    ) {
                        model.chooseReturn("one_way")
                    }
                    choice(
                        "Add my return flight", hint: "We plan the shift back home too",
                        selected: model.choicePending && model.draft.form.end.kind == "return_legs", id: "add-return",
                        enabled: model.draft.form.end.kind == "return_legs"
                            || model.draft.form.legs.count < WizardForm.maxFlights
                    ) { model.chooseReturn("return_legs") }
                }
            }
        }

        var returnFlightScreen: some View { timesScreen(home: true) }

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
            let sleep = id.hasPrefix("sleep.")
            let question = id.hasPrefix("question.")
            let radius =
                sleep ? PlanUITokens.radiusXl : question ? PlanUITokens.wizardQuestionRadius : PlanUITokens.radius2Xl
            return Button {
                UISelectionFeedbackGenerator().selectionChanged()
                action()
            } label: {
                HStack(spacing: PlanUITokens.space3) {
                    VStack(alignment: .leading, spacing: sleep ? PlanUITokens.wizardLabelGap : 0) {
                        Text(t(label)).font((sleep ? Typography.wizardChronotype : Typography.wizardChoice).font)
                        if let hint {
                            Text(t(hint)).font((sleep ? Typography.wizardHint : Typography.screenBody).font)
                                .foregroundStyle(ColorToken.mutedForeground.color)
                        }
                    }
                    Spacer(minLength: 0)
                    if !sleep && !question {
                        Image(systemName: id == "web" ? "checkmark" : "chevron.right")
                            .font(.system(size: id == "web" ? PlanUITokens.space5 : PlanUITokens.space4))
                            .foregroundStyle((id == "web" ? ColorToken.dawnText : .mutedForeground).color)
                    }
                }
                .padding(.leading, sleep ? PlanUITokens.wizardContentGap : PlanUITokens.space5)
                .padding(
                    .trailing,
                    sleep ? PlanUITokens.wizardContentGap : question ? PlanUITokens.space5 : PlanUITokens.space4
                )
                .padding(.vertical, sleep ? PlanUITokens.wizardChronotypePadding : question ? 0 : PlanUITokens.space3)
                .frame(
                    maxWidth: .infinity,
                    minHeight: question ? PlanUITokens.wizardFlightRowHeight : PlanUITokens.wizardChoiceHeight,
                    alignment: .leading
                )
                .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(
                        (selected ? ColorToken.dawn : .border).color, lineWidth: AuthTokens.focusWidth)
                }
            }.buttonStyle(.plain).disabled(!enabled || model.choicePending)
                .accessibilityIdentifier("wizard.choice.\(id)")
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

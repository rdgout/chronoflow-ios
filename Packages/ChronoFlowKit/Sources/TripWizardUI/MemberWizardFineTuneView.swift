#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        private func preferenceToggle(_ field: String, _ title: String, hint: String) -> some View {
            Toggle(
                isOn: Binding(
                    get: { model.preference(field) },
                    set: { value in model.setPreference(field, value: value) }
                )
            ) {
                VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                    Text(t(title)).font(Typography.wizardChronotype.font)
                    Text(t(hint)).font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                }
            }.padding(PlanUITokens.space4).accessibilityIdentifier("wizard.preference." + field)
        }
        var fineTuneScreen: some View {
            wizardShell(
                title: t("Fine-tune your plan"),
                subtitle: t(
                    model.optionalPrompts.isEmpty
                        ? "No extra questions for this trip. You can still change these."
                        : "All optional. The ones marked help your plan most."),
                id: "fine-tune",
                button: t(model.reviewing ? "Checking…" : model.optionalPrompts.isEmpty ? "Done" : "Continue"),
                enabled: !model.reviewing, action: { model.finishFineTune() },
                content: {
                    VStack(spacing: 0) {
                        preferenceToggle(
                            "exclude_caffeine", "Leave caffeine out of my plan",
                            hint: "Your plan won't suggest any caffeine.")
                        Divider().overlay(ColorToken.border.color)
                        preferenceToggle(
                            "flight_movement_breaks", "Add movement breaks during long-flight sleep",
                            hint:
                                "Your plan breaks up long sleep on long flights with short movement breaks. If you're at higher risk of blood clots, choose this and ask your doctor about compression stockings and an aisle seat."
                        )
                    }.wizardCard().disabled(model.reviewing)
                    if !model.optionalPrompts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(model.optionalPrompts.enumerated()), id: \.element.id) { index, prompt in
                                if index > 0 { Divider().overlay(ColorToken.border.color) }
                                Button {
                                    model.openPrompt(prompt.id)
                                } label: {
                                    HStack(spacing: PlanUITokens.space2) {
                                        VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                                            Text(optionalLabel(prompt)).font(Typography.wizardChronotype.font)
                                            if prompt.required {
                                                Label(t("Helps a lot"), systemImage: "star.fill")
                                                    .font(Typography.screenMeta.font).foregroundStyle(
                                                        ColorToken.dawnText.color)
                                            }
                                            if let error = WizardPresentation.promptFieldError(
                                                prompt, form: model.draft.form, errors: model.draft.fieldErrors)
                                            {
                                                errorLine(
                                                    fieldCopy(error), identifier: "wizard.extra.error.\(prompt.id)")
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        let answer = try? WizardPresentation.promptAnswerText(
                                            prompt, input: model.reviewInput, locale: locale, t: t)
                                        Text(answer ?? t("Add"))
                                            .font(Typography.wizardNavTitle.font)
                                            .foregroundStyle((answer == nil ? ColorToken.dawnText : .foreground).color)
                                        Image(systemName: "chevron.right").foregroundStyle(
                                            ColorToken.mutedForeground.color
                                        )
                                        .accessibilityHidden(true)
                                    }.padding(.horizontal, PlanUITokens.space4).frame(
                                        minHeight: PlanUITokens.wizardButtonHeight)
                                }.buttonStyle(.plain).accessibilityIdentifier(
                                    "wizard.extra.\(prompt.kind.rawValue).\(index)")
                            }
                        }.wizardCard().disabled(model.reviewing)
                            .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.extras")
                    }
                    VStack(spacing: 0) {
                        Stepper(
                            value: Binding(
                                get: { model.draft.form.preparation.days },
                                set: { value in
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    model.editForm { $0.preparation.days = value }
                                }), in: 0...WizardForm.maxPreparationDays
                        ) {
                            VStack(alignment: .leading) {
                                Text(t("Preparation days"))
                                Text(t("Before you leave")).font(Typography.wizardHint.font).foregroundStyle(
                                    ColorToken.mutedForeground.color)
                            }
                            Text(model.draft.form.preparation.days.formatted(.number.locale(locale))).monospacedDigit()
                        }.padding(PlanUITokens.space4).accessibilityIdentifier("wizard.preparation")
                        if model.allowsSleepOverride {
                            Divider().overlay(ColorToken.border.color)
                            Toggle(
                                t("Use different sleep times for this trip"),
                                isOn: Binding(
                                    get: { model.draft.form.override.enabled },
                                    set: { enabled in
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        model.editForm { form in
                                            form.override.enabled = enabled
                                            if enabled {
                                                form.override.habitualBed =
                                                    form.override.habitualBed ?? model.draft.state.profile[
                                                        "habitual_bed"]?
                                                    .string ?? model.draft.state.savedProfile?["habitualBed"]?.string
                                                form.override.habitualWake =
                                                    form.override.habitualWake ?? model.draft.state.profile[
                                                        "habitual_wake"]?
                                                    .string ?? model.draft.state.savedProfile?["habitualWake"]?.string
                                            }
                                        }
                                    })
                            ).padding(PlanUITokens.space4).tint(ColorToken.dawn.color).accessibilityIdentifier(
                                "wizard.sleep-override")
                        }
                        if model.allowsSleepOverride, model.draft.form.override.enabled {
                            overrideTime("Bedtime on this trip", wake: false)
                            overrideTime("Wake-up on this trip", wake: true)
                            Text(t("Only for this trip. Your usual sleep stays saved."))
                                .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                                .padding(
                                    PlanUITokens.space4)
                        }
                        ForEach(
                            model.draft.fieldErrors.keys.filter {
                                $0.hasPrefix("override.") || $0.hasPrefix("preparation.")
                            }.sorted(), id: \.self
                        ) { field in
                            errorLine(
                                fieldCopy(model.draft.fieldErrors[field]!),
                                identifier: "wizard.fine-tune.error.\(field)"
                            ).padding(PlanUITokens.space4)
                        }
                    }.font(Typography.wizardChronotype.font).wizardCard().disabled(model.reviewing)
                })
        }

        func overrideTime(_ key: String, wake: Bool) -> some View {
            WizardTimeControl(
                label: t(key),
                value: Binding(
                    get: {
                        wake
                            ? model.draft.form.override.habitualWake ?? "" : model.draft.form.override.habitualBed ?? ""
                    },
                    set: { value in
                        model.editForm { form in
                            if wake { form.override.habitualWake = value } else { form.override.habitualBed = value }
                        }
                    })
            ).padding(PlanUITokens.space4)
        }

        func optionalLabel(_ prompt: ApiReviewPrompt) -> String {
            let label = t(WizardPromptLabels.key(prompt))
            let index =
                (prompt.scope.journey == .return ? model.draft.form.returnBoundary : 0)
                + (prompt.scope.legIndex ?? prompt.scope.stayIndex ?? 0)
            guard model.draft.form.legs.count > 1, model.draft.form.legs.indices.contains(index) else { return label }
            let leg = model.draft.form.legs[index]
            if prompt.kind == .seatSide { return label + " · " + leg.fromIata + " → " + leg.toIata }
            if prompt.kind == .room || prompt.kind == .lateCheckOut {
                return (prompt.kind == .room ? t("Dark room") : label) + " · " + (leg.toCity ?? leg.toIata)
            }
            return label
        }
    }

    enum WizardPromptLabels {
        static func key(_ prompt: ApiReviewPrompt) -> String {
            switch prompt.kind {
            case .seatSide: "Side of the plane"
            case .room: "Dark room at your stay"
            case .lateCheckOut: "Late check-out"
            case .latestWake: "Latest you can wake up"
            case .preDepartureBusyHours: "Busy hours before you leave"
            case .freeDayTimes: "Sleep on free days"
            case .cups: "Coffee, tea and soft drinks"
            case .lightDevice: "Light box or light glasses"
            case .blueBlockers: "Blue-blocking glasses"
            default: prompt.text.key
            }
        }
    }

    struct WizardTimeControl: View {
        let label: String
        @Binding var value: String
        var body: some View {
            DatePicker(
                label,
                selection: Binding(
                    get: {
                        WizardDateTime.date("2000-01-01T" + String(value.suffix(5))) ?? WizardDateTime.date(
                            "2000-01-01T12:00")!
                    },
                    set: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        value = String(WizardDateTime.string($0).suffix(5))
                    }), displayedComponents: .hourAndMinute
            )
            .environment(\.calendar, WizardDateTime.calendar).environment(\.timeZone, WizardDateTime.calendar.timeZone)
            .font(Typography.wizardRow.font)
        }
    }
#endif

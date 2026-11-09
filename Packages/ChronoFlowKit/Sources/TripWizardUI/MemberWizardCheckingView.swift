#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        var checkingLines: [String] {
            model.draft.state.checkingAnswers == true
                ? ["Your answers", "Flights and time zones", "What we can tailor"]
                : ["Flights and time zones", "Your saved answers", "What we can tailor"]
        }
        var checkingScreen: some View {
            wizardShell(
                title: t(model.draft.state.checkingAnswers == true ? "Checking your answers" : "Checking your trip"),
                subtitle: model.checking.failure == nil ? t("This takes a few seconds.") : nil, id: "checking",
                button: model.checking.failure == nil
                    ? nil
                    : (model.retrySeconds > 0
                        ? t("Try again in {{count}} s", ["count": String(model.retrySeconds)]) : t("Try again")),
                enabled: model.retrySeconds == 0, action: { model.beginChecking() },
                content: {
                    if let failure = model.checking.failure {
                        checkFailure(failure)
                    } else {
                        VStack(alignment: .leading, spacing: PlanUITokens.wizardCheckingGap) {
                            WizardCheckingArc(
                                from: model.draft.form.legs[0].fromIata,
                                to: model.draft.form.legs[model.draft.form.returnBoundary - 1].toIata)
                            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                                ForEach(Array(checkingLines.enumerated()), id: \.offset) { index, line in
                                    WizardCheckLine(
                                        label: t(line), done: model.checking.ticks > index,
                                        busy: model.checking.ticks == index,
                                        accessibility: checkLineLabel(index))
                                }
                            }
                            if model.checking.slow {
                                Text(t("This is taking longer than usual. You can keep this screen open."))
                                    .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                                    .accessibilityIdentifier("wizard.checking.slow")
                            }
                        }.padding(.horizontal, PlanUITokens.space5).padding(
                            .vertical, PlanUITokens.wizardCheckingPadding
                        )
                        .background(
                            ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                                ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                        }
                        .background {
                            let spread = scheme == .dark ? AuthTokens.darkShadowSpread : AuthTokens.lightShadowSpread
                            RoundedRectangle(cornerRadius: max(0, PlanUITokens.radius3Xl + spread))
                                .fill(ColorToken.card.color)
                                .shadow(
                                    color: ColorToken.authShadow.color,
                                    radius: scheme == .dark
                                        ? AuthTokens.darkShadowRadius : AuthTokens.lightShadowRadius,
                                    y: scheme == .dark ? AuthTokens.darkShadowY : AuthTokens.lightShadowY
                                )
                                .padding(-spread)
                        }
                    }
                }
            )
            .onAppear {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: t(
                        model.draft.state.checkingAnswers == true ? "Checking your answers" : "Checking your trip"))
                model.resumeChecking()
            }
            .onChange(of: model.checking.ticks) { previous, next in
                if next > previous, (1...3).contains(next) {
                    UIAccessibility.post(notification: .announcement, argument: checkLineLabel(next - 1))
                    if next < 3 { UIAccessibility.post(notification: .announcement, argument: checkLineLabel(next)) }
                }
            }
            .onChange(of: model.draft.state.step) { previous, next in
                if previous == .checking, next != .checking {
                    UINotificationFeedbackGenerator().notificationOccurred(next == .excluded ? .warning : .success)
                }
            }
            .onChange(of: model.checking.failure) { _, next in
                if next != nil { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
        }

        func checkLineLabel(_ index: Int) -> String {
            t(
                model.checking.ticks > index
                    ? "{{line}}, done" : model.checking.ticks == index ? "{{line}}, in progress" : "{{line}}",
                ["line": t(checkingLines[index])])
        }

        func checkFailure(_ failure: DataFailure) -> some View {
            let kind: String
            let title: String
            let body: String
            let symbol: String
            switch failure {
            case .offline:
                kind = "offline"
                title = "Checking needs a connection"
                body = "Connect to the internet and try again."
                symbol = "icloud.slash"
            case .throttled:
                kind = "throttle"
                title = "Wait a moment"
                symbol = "clock"
                body =
                    model.retrySeconds > 0
                    ? "Too many attempts. Try again in {{count}} seconds."
                    : "Too many attempts. Please try again later."
            default:
                kind = "server"
                title = "We couldn't check your trip"
                body = "Something went wrong on our side. Try again in a moment."
                symbol = "exclamationmark.circle"
            }
            return VStack(spacing: PlanUITokens.space3) {
                Image(systemName: symbol).font(.system(size: PlanUITokens.wizardFailureIconSize)).foregroundStyle(
                    ColorToken.mutedForeground.color
                )
                .frame(width: PlanUITokens.wizardFailureIconCircle, height: PlanUITokens.wizardFailureIconCircle)
                .background(
                    ColorToken.muted.color, in: Circle()
                ).accessibilityHidden(true)
                WelcomeText(t(title), style: Typography.wizardFailureTitle, color: .foreground)
                WelcomeText(
                    t(body, ["count": String(model.retrySeconds)]), style: Typography.wizardFailureBody,
                    color: .mutedForeground)
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.horizontal, PlanUITokens.space5).padding(.vertical, PlanUITokens.wizardFailurePadding)
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                        ColorToken.border.color,
                        style: StrokeStyle(
                            lineWidth: AuthTokens.borderWidth,
                            dash: [PlanUITokens.wizardFailureDashLength, PlanUITokens.wizardFailureDashLength]))
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("wizard.checking.\(kind)")
        }

        @ViewBuilder func questionScreen(_ index: Int) -> some View {
            let questions = model.draft.state.questions ?? []
            if questions.indices.contains(index) {
                let prompt = questions[index]
                wizardShell(
                    title: serverCopy(prompt.text), eyebrow: t("A few quick questions"), id: "question.\(index)",
                    answerHint: true
                ) {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardChoiceGap) {
                        if let field = prompt.fields.first {
                            if prompt.kind == .screening, prompt.shape.kind == .boolean {
                                ForEach([false, true], id: \.self) { value in
                                    choice(
                                        value ? "Yes" : "No",
                                        selected: model.draft.state.profile[field] == .bool(value),
                                        id: "question.\(value)"
                                    ) {
                                        model.answerQuestion(.bool(value))
                                    }
                                }
                            } else if prompt.kind == .ageBand {
                                ForEach(prompt.shape.options, id: \.self) { value in
                                    let labels = ["under_18": "Under 18", "18_64": "18–64", "65_plus": "65 or older"]
                                    choice(
                                        labels[value] ?? value,
                                        selected: model.draft.state.profile[field] == .string(value),
                                        id: "question.\(value)"
                                    ) {
                                        model.answerQuestion(.string(value))
                                    }
                                }
                            }
                            if let why = Self.questionWhy[field] {
                                Text(t(why)).font(Typography.wizardHint.font).foregroundStyle(
                                    ColorToken.mutedForeground.color
                                )
                                .padding(.top, PlanUITokens.space1).padding(.horizontal, PlanUITokens.space1)
                            }
                        }
                    }
                }
            }
        }

        static var questionWhy: [String: String] {
            [
                "age_band": "Light and sleep advice differs by age.",
                "shift_work": "Shift work changes how we can plan your clock.",
                "caffeine_ruled_out": "If so, we leave coffee and tea out of your plan.",
                "eye_disease": "Some light advice isn't safe for sensitive eyes.",
                "vte": "Then we add more movement on long flights.",
                "bipolar": "Shifting sleep and light can affect mood, so we check first.",
                "pregnancy": "Some advice, like caffeine timing, changes when you're pregnant or breastfeeding.",
            ]
        }

        var excludedScreen: some View {
            wizardShell(
                title: t("No plan available"), id: "excluded", button: t("Change my answers"),
                action: { model.changeExcludedAnswers() },
                content: {
                    VStack(alignment: .leading, spacing: PlanUITokens.wizardChoiceGap) {
                        ForEach(Array((model.draft.state.review?.reasons ?? []).enumerated()), id: \.offset) {
                            _, line in
                            WelcomeText(serverCopy(line), style: Typography.screenBodyLg, color: .foreground)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(PlanUITokens.space5)
                        .background(
                            ColorToken.wizardNoticeBackground.color,
                            in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                                ColorToken.wizardNoticeBorder.color, lineWidth: AuthTokens.borderWidth)
                        }
                    Text(
                        t(
                            model.exclusionWasSaved
                                ? "You gave this answer on an earlier trip. Change it to plan this trip."
                                : "If you answered by mistake, you can change your answers.")
                    )
                    .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                })
        }
    }

    private struct WizardCheckLine: View {
        @Environment(\.accessibilityReduceMotion) var reduced
        let label: String
        let done: Bool
        let busy: Bool
        let accessibility: String
        var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                ZStack {
                    Circle().fill((done ? ColorToken.dawn : .muted).color)
                    if done {
                        Image(systemName: "checkmark").font(Typography.screenLabel.font).foregroundStyle(
                            ColorToken.dawnForeground.color)
                    } else if busy {
                        if reduced {
                            Circle().fill(ColorToken.mutedForeground.color).padding(PlanUITokens.space2)
                        } else {
                            ProgressView().controlSize(.mini).tint(ColorToken.mutedForeground.color)
                                .frame(width: PlanUITokens.wizardSpinnerSize, height: PlanUITokens.wizardSpinnerSize)
                        }
                    }
                }.frame(width: PlanUITokens.space6, height: PlanUITokens.space6).accessibilityHidden(true)
                Text(label).font(Typography.wizardSubtitle.font).foregroundStyle(
                    (done ? ColorToken.foreground : .mutedForeground).color)
            }.accessibilityElement(children: .ignore).accessibilityLabel(accessibility)
        }
    }

    private struct WizardCheckingArc: View {
        @Environment(\.accessibilityReduceMotion) var reduced
        let from: String
        let to: String
        var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                Text(from).font(Typography.wizardArc.font)
                TimelineView(.animation(paused: reduced)) { context in
                    Canvas { graphics, size in
                        let inset = PlanUITokens.space2
                        let width = max(0, size.width - inset * 2)
                        let height = max(0, size.height - inset * 2)
                        var arc = Path()
                        arc.move(to: CGPoint(x: inset, y: inset + height))
                        arc.addQuadCurve(
                            to: CGPoint(x: inset + width, y: inset + height),
                            control: CGPoint(x: size.width / 2, y: inset - height))
                        graphics.stroke(
                            arc, with: .color(ColorToken.dawn.color),
                            style: StrokeStyle(
                                lineWidth: AuthTokens.focusWidth,
                                dash: [PlanUITokens.space1, PlanUITokens.wizardControlGap]))
                        let phase =
                            reduced ? 0.65 : (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.8) + 1) / 2
                        let point = CGPoint(
                            x: inset + width * phase, y: inset + height * (1 - 2 * phase) * (1 - 2 * phase))
                        let radius = PlanUITokens.wizardArcDotRadius
                        graphics.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(ColorToken.dawn.color))
                    }
                }.frame(height: PlanUITokens.wizardArcHeight)
                Text(to).font(Typography.wizardArc.font)
            }.accessibilityHidden(true)
        }
    }
#endif

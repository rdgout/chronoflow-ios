#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import TripWizard
    import UIKit

    extension MemberWizardView {
        var readyScreen: some View {
            wizardShell(
                title: t("Ready to plan"), id: "ready",
                button: model.credits == .unavailable ? nil : t(readyButton, ["count": String(model.retrySeconds)]),
                enabled: model.canSave && model.credits != .unavailable,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.savePlan()
                }
            ) {
                if let failure = model.draft.state.saveFailure {
                    saveFailureBanner(failure)
                } else if model.draft.state.review?.status == .modified {
                    readyBanner(
                        title: t("We adjusted your plan"),
                        body: (model.draft.state.review?.reasons ?? []).map(serverCopy).joined(separator: " "))
                } else if model.draft.state.updated == true {
                    readyBanner(title: t("Updated"), body: updatedSummary)
                }
                if let summary = model.draft.state.review?.summary {
                    VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                        Text(t("Your plan").uppercased()).font(Typography.screenEyebrow.font).tracking(
                            Typography.screenEyebrow.tracking
                        )
                        .foregroundStyle(ColorToken.dawnText.color)
                        WelcomeText(serverCopy(summary.line), style: Typography.wizardReadySummary, color: .foreground)
                        Text(
                            WizardPresentation.planDateSummary(model.draft.form, summary: summary, locale: locale, t: t)
                        )
                        .font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                        .monospacedDigit()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PlanUITokens.wizardReadySummaryPadding).padding(
                            .vertical, PlanUITokens.space4
                        )
                        .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl))
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                                ColorToken.dawn.color, lineWidth: AuthTokens.focusWidth)
                        }
                        .accessibilityIdentifier("wizard.ready.summary")
                }
                VStack(spacing: 0) {
                    readyRow("Route", value: routeSummary, step: .whereTo)
                    readyRow(
                        "Flight", value: WizardPresentation.flightSummary(model.draft.form, locale: locale, t: t),
                        step: .outbound)
                    readyRow(
                        "Return",
                        value: WizardPresentation.returnSummary(
                            model.draft.form, stayEnd: model.draft.state.review?.summary?.stayEnd, locale: locale, t: t),
                        step: .returnChoice)
                    readyRow("Sleep", value: sleepSummary, step: .fineTune, sleep: true)
                    readyRow(
                        "Extras",
                        value: (try? WizardPresentation.extrasSummary(
                            model.draft.form, review: model.draft.state.review, input: model.reviewInput,
                            locale: locale, t: t)) ?? "", step: .fineTune)
                    if model.draft.state.review?.status == .modified,
                        let prompt = model.optionalPrompts.first(where: { $0.kind == .latestWake })
                    {
                        Button {
                            model.revisit(.fineTune)
                            model.openPrompt(prompt.id)
                        } label: {
                            readyRowContent(
                                "Latest wake-up",
                                value: (try? WizardPresentation.promptAnswerText(
                                    prompt, input: model.reviewInput, locale: locale, t: t)) ?? "")
                        }.buttonStyle(.plain)
                    }
                }.wizardCard().disabled(model.reviewing)
                priceBlock

            }
            .task {
                while !Task.isCancelled {
                    model.readyTick()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.readyTick(force: model.credits == .unavailable) }
            }
            .onChange(of: model.draft.state.saveFailure) { _, value in
                if value != nil { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
        }
        private var readyButton: String {
            if model.reviewing { return "Checking…" }
            if model.draft.state.saveFailure?.kind == .throttle {
                return model.retrySeconds > 0 ? "Try again in {{count}} s" : "Try again"
            }
            return "Make my plan"
        }
        private var routeSummary: String {
            (model.draft.form.legs.first?.fromIata ?? "") + " → "
                + (model.draft.form.legs.prefix(model.draft.form.returnBoundary).last?.toIata ?? "")
        }
        private var sleepSummary: String {
            let override = model.draft.form.override
            let bed =
                override.enabled
                ? override.habitualBed
                : model.draft.state.profile["habitual_bed"]?.string
                    ?? model.draft.state.savedProfile?["habitualBed"]?.string
            let wake =
                override.enabled
                ? override.habitualWake
                : model.draft.state.profile["habitual_wake"]?.string
                    ?? model.draft.state.savedProfile?["habitualWake"]?.string
            let times = [bed, wake].compactMap { $0 }.joined(separator: "–")
            return override.enabled ? t("This trip · {{times}}", ["times": times]) : times
        }
        private var price: String {
            guard let review = model.draft.state.review else { return "" }
            if review.price.unlimited { return t("Included in your subscription.") }
            return review.price.cost == 0
                ? t("Free")
                : t(
                    review.price.cost == 1 ? "{{count}} credit" : "{{count}} credits",
                    ["count": String(review.price.cost)])
        }
        private var updatedSummary: String {
            [model.draft.state.review?.summary.map { serverCopy($0.line) } ?? "", t("Price") + ": " + price].joined(
                separator: " ")
        }
        private var priceBlock: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.wizardControlGap) {
                Text(model.credits == .unlimited ? price : t("Price") + " " + price).font(
                    Typography.wizardSubtitle.font)
                if model.credits == .free {
                    Text(t("This trip is free: only a small body-clock shift is needed."))
                }
                if model.credits == .oneFree {
                    Text(t("Your flight home is free: only a small shift is needed that way."))
                }
                if let review = model.draft.state.review, !review.price.unlimited, review.price.cost > 0 {
                    Text(t("You have {{count}} credits.", ["count": String(review.price.balance)]))
                        .foregroundStyle(
                            (model.credits == .unavailable ? ColorToken.destructive : .mutedForeground).color)
                }
            }.font(Typography.wizardHint.font).foregroundStyle(ColorToken.mutedForeground.color)
                .accessibilityIdentifier("wizard.ready.price")
        }
        private func readyRow(_ key: String, value: String, step: MemberWizardStep, sleep: Bool = false) -> some View {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                model.revisit(step, sleep: sleep)
            } label: {
                readyRowContent(key, value: value)
            }.buttonStyle(.plain)
                .accessibilityHint(t("Opens this step")).accessibilityIdentifier("wizard.ready.\(key.lowercased())")
        }
        private func readyRowContent(_ key: String, value: String) -> some View {
            VStack(spacing: 0) {
                if key != "Route" { Divider().overlay(ColorToken.border.color) }
                HStack(spacing: PlanUITokens.space2) {
                    Group {
                        if dynamicTypeSize <= .xLarge {
                            HStack(alignment: .firstTextBaseline, spacing: PlanUITokens.space2) {
                                Text(t(key)).foregroundStyle(ColorToken.mutedForeground.color).frame(
                                    width: PlanUITokens.wizardReadyLabelWidth, alignment: .leading)
                                Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                                Text(t(key)).foregroundStyle(ColorToken.mutedForeground.color)
                                Text(value).monospacedDigit()
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Image(systemName: "chevron.right").foregroundStyle(ColorToken.mutedForeground.color)
                        .accessibilityHidden(true)
                }.font(Typography.screenBody.font).padding(.horizontal, PlanUITokens.space4).padding(
                    .vertical, PlanUITokens.space2
                )
                .frame(minHeight: PlanUITokens.actionMinHeight)
            }
        }
        func readyBanner(title: String, body: String, failure: Bool = false) -> some View {
            VStack(alignment: .leading, spacing: PlanUITokens.wizardLabelGap) {
                Text(title).font(Typography.screenLabel.font)
                Text(body).font(Typography.screenBody.font)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(PlanUITokens.wizardContentGap)
                .background(
                    (failure ? ColorToken.authErrorBackground : .wizardNoticeBackground).color,
                    in: RoundedRectangle(cornerRadius: PlanUITokens.radiusXl)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radiusXl).strokeBorder(
                        (failure ? ColorToken.authErrorBorder : .wizardNoticeBorder).color,
                        lineWidth: AuthTokens.borderWidth)
                }
        }
        private func saveFailureBanner(_ failure: WizardSaveFailure) -> some View {
            let title: String
            let body: String
            switch failure.kind {
            case .offline:
                title = "Saving needs a connection"
                body =
                    "Connect to the internet and tap Make my plan again. Keep this screen open: closing discards the trip."
            case .server:
                title = "We couldn't save your plan"
                body = "Something went wrong on our side. Tap Make my plan to try again."
            case .throttle:
                title = "Wait a moment"
                body =
                    model.retrySeconds > 0
                    ? "Too many attempts. Try again in {{count}} seconds."
                    : "Too many attempts. Please try again later."
            }
            return readyBanner(title: t(title), body: t(body, ["count": String(model.retrySeconds)]), failure: true)
                .accessibilityIdentifier("wizard.save.\(failure.kind.rawValue)")
        }
        var calculatingScreen: some View {
            wizardShell(
                title: t("Calculating your plan…"),
                subtitle: t("This can take up to a minute. You can keep this screen open."), id: "calculating"
            ) {
                VStack(spacing: PlanUITokens.space4) {
                    if reduceMotion {
                        Image(systemName: "clock").font(.system(size: PlanUITokens.wizardFailureIconSize))
                            .foregroundStyle(ColorToken.dawnText.color)
                    } else {
                        ProgressView().controlSize(.large).tint(ColorToken.dawnText.color)
                    }
                    Text(
                        routeSummary + " · "
                            + t(
                                "{{count}} days of steps",
                                [
                                    "count": String(
                                        WizardPresentation.planDayCount(model.draft.state.review?.summary) ?? 0)
                                ])
                    )
                    .font(Typography.wizardFailureBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(PlanUITokens.space8).wizardCard()
            }.background { WizardSaveLock() }
                .onAppear { UIAccessibility.post(notification: .announcement, argument: t("Calculating your plan…")) }
        }
    }

    private struct WizardSaveLock: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Controller { Controller() }
        func updateUIViewController(_ controller: Controller, context: Context) {}
        final class Controller: UIViewController {
            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            }
            override func viewWillDisappear(_ animated: Bool) {
                navigationController?.interactivePopGestureRecognizer?.isEnabled = true
                super.viewWillDisappear(animated)
            }
        }
    }
#endif

#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct StepSheet: View {
        @Environment(\.locale) private var locale
        @Environment(\.dismiss) private var dismiss
        #if DEBUG
            @Environment(\.planUITestOptions) private var uiTestOptions
        #endif
        @ScaledMetric(relativeTo: .body) private var titleLineHeight =
            Typography.screenCardTitle.lineHeight ?? Typography.screenCardTitle.size
        private enum ActionFocus: Hashable { case done, undo }
        @AccessibilityFocusState private var actionFocus: ActionFocus?
        public let detail: TripDetail?
        public let blockID: String
        public let now: Date
        public let formatter: CopyLineFormatter
        public var timeFormat: TimeFormat = .value24
        public var busy = false
        public var change: (CheckStatus?) async -> Void

        public init(
            detail: TripDetail?, blockID: String, now: Date, formatter: CopyLineFormatter,
            timeFormat: TimeFormat = .value24, busy: Bool = false,
            change: @escaping (CheckStatus?) async -> Void
        ) {
            self.detail = detail
            self.blockID = blockID
            self.now = now
            self.formatter = formatter
            self.timeFormat = timeFormat
            self.busy = busy
            self.change = change
        }

        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String, _ values: [String: String] = [:]) -> String {
            PlanStrings.text(key, language: language, values)
        }
        private var markStatus: CheckStatus? {
            guard let detail, let block = detail.plan.blocks.first(where: { $0.id == blockID }),
                let key = block.checkKey
            else { return nil }
            return detail.checkState.marks.first { checkIdentity($0.key) == checkIdentity(key) }?.status
        }
        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                    if let detail, let block = detail.plan.blocks.first(where: { $0.id == blockID }) {
                        content(detail, block)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .overlay {
                                Image(systemName: "xmark").font(.system(size: PlanUITokens.stepGoneIconSize / 2))
                                    .offset(
                                        x: -PlanUITokens.stepGoneIconSize / 12, y: -PlanUITokens.stepGoneIconSize / 12)
                            }
                            .font(.system(size: PlanUITokens.stepGoneIconSize))
                            .frame(width: PlanUITokens.stepGoneCircleSize, height: PlanUITokens.stepGoneCircleSize)
                            .foregroundStyle(ColorToken.dawnText.color)
                            .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                        Text(t("This step is no longer in your plan")).planTextStyle(Typography.screenCardTitle)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("step.gone")
                        Text(
                            t(
                                "Your plan changed after you opened it, for example because you edited the trip. Your other check-offs are kept."
                            )
                        ).foregroundStyle(ColorToken.mutedForeground.color)
                        AuthButton(t("See today's steps"), minimumHeight: PlanUITokens.actionMinHeight) { dismiss() }
                    }
                }.planContentBounds().padding(PlanUITokens.space5).padding(.top, PlanUITokens.space4).planPageRail()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { RefusedChangeFeedback() }
            .tint(ColorToken.primary.color).controlSize(.large)
            .font(Typography.screenBodyLg.font).foregroundStyle(ColorToken.cardForeground.color)
            .background(ColorToken.card.color).accessibilityIdentifier("step.sheet")
            .presentationDragIndicator(.visible).presentationDetents(detents)
            .onChange(of: markStatus) { _, status in
                guard detail?.plan.blocks.contains(where: { $0.id == blockID }) == true else { return }
                AccessibilityNotification.Announcement(
                    t(status == .done ? "Done" : status == .skipped ? "Skipped" : "Check-off undone")
                ).post()
                actionFocus = status == nil ? .done : .undo
            }
        }

        private var detents: Set<PresentationDetent> {
            #if DEBUG
                if uiTestOptions.largeStepSheet { return [.large] }
            #endif
            return [.medium, .large]
        }

        @ViewBuilder private func content(_ detail: TripDetail, _ block: BlockView) -> some View {
            let key = block.actionable ? block.checkKey : nil
            let mark = key.flatMap { key in
                detail.checkState.marks.first { checkIdentity($0.key) == checkIdentity(key) }
            }
            let running = planDate(block.startUtc) <= now && now < planDate(block.endUtc)
            let options = CopyFormat(
                language: language, timeFormat: timeFormat, displayZone: block.displayTz,
                annotateInstantZone: true, trip: detail.trip)
            let interval =
                block.type == .zoneChange
                ? formatter.formatInstant(block.startUtc, options: options)
                : formatter.blockInterval(block, options: options, separator: " → ")
            let time = t(
                "{{time}} {{zone}} time", ["time": interval, "zone": zoneLabel(block.displayTz, trip: detail.trip)])
            HStack(alignment: .top, spacing: PlanUITokens.space3) {
                CategorySwatch(block.type)
                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                    ViewThatFits(in: .horizontal) {
                        HStack { badges(block, mark: mark, running: running) }
                        VStack(alignment: .leading) { badges(block, mark: mark, running: running) }
                    }
                    Text(t(stepLabelKey(block.type) ?? "Note"))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: titleLineHeight, alignment: .leading)
                        .planTextStyle(Typography.screenCardTitle, context: "step.title")
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        running
                            ? time + " · "
                                + t(
                                    "{{duration}} left",
                                    [
                                        "duration": formatter.formatMinutes(
                                            max(0, ceil(planDate(block.endUtc).timeIntervalSince(now) / 60)),
                                            language: language, duration: true)
                                    ]) : time
                    )
                    .planTextStyle(Typography.screenBody, color: .mutedForeground, context: "step.time")
                    .monospacedDigit()
                }
            }
            let reasons = detail.timeline.blockReasons.first { $0.blockId == block.id }?.lines ?? []
            if !reasons.isEmpty {
                section("Why", lines: reasons, options: options)
            }
            let instructions: [CopyLine] = {
                if case .note(let params) = block.params { return params.note.lines }
                return [block.text] + (block.secondaryText.map { [$0] } ?? [])
            }()
            section("How", lines: instructions, options: options, bullets: true)
            if key != nil {
                if mark != nil {
                    AuthButton(t("Undo"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight) {
                        Task { await change(nil) }
                    }.accessibilityFocused($actionFocus, equals: .undo)
                        .accessibilityIdentifier("step.undo").disabled(busy)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: PlanUITokens.space2) { actions }
                        VStack(spacing: PlanUITokens.space2) { actions }
                    }.disabled(busy)
                }
            }
            Text(t("Checking off changes your progress, never your plan."))
                .planTextStyle(Typography.screenMeta, color: .mutedForeground, context: "step.footer")
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        @ViewBuilder private var actions: some View {
            AuthButton(t("Skip"), kind: .outline, minimumHeight: PlanUITokens.actionMinHeight) {
                Task { await change(.skipped) }
            }.accessibilityIdentifier("step.skip")
            AuthButton(t("Mark as done"), glyph: .check, minimumHeight: PlanUITokens.actionMinHeight) {
                Task { await change(.done) }
            }.accessibilityFocused($actionFocus, equals: .done)
                .accessibilityIdentifier("step.done")
        }
        @ViewBuilder private func badges(_ block: BlockView, mark: CheckMark?, running: Bool) -> some View {
            PriorityTag(text: t(priorityKey(block.priority)))
            if let mark {
                PlanBadge(
                    text: t(mark.status == .done ? "Done" : "Skipped"),
                    variant: mark.status == .done ? .secondary : .outline)
            } else if running {
                PlanBadge(text: t("Now"), active: true)
            }
        }
        private func section(_ title: String, lines: [CopyLine], options: CopyFormat, bullets: Bool = false)
            -> some View
        {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                Text(t(title).uppercased()).planTextStyle(Typography.screenLabel, color: .mutedForeground)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: PlanUITokens.space3) {
                        if bullets {
                            Circle().frame(width: PlanUITokens.space1, height: PlanUITokens.space1)
                                .padding(.top, PlanUITokens.space2).accessibilityHidden(true)
                        }
                        Text(formatter.format(line, options: options))
                    }
                }
            }
        }
    }

#endif

#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct TodayScreen: View {
        @Environment(\.locale) private var locale
        public let trips: [TripListValue]
        public let detail: TripDetail?
        public let now: Date
        public let loading: Bool
        public let formatter: CopyLineFormatter
        public var hidden: [BlockType]
        public var timeFormat: TimeFormat
        public var openTrip: (String) -> Void
        public var openStep: (String) -> Void
        public var settings: () -> Void
        public var pastTrips: () -> Void
        public var refresh: () async -> Void
        public init(
            trips: [TripListValue], detail: TripDetail?, now: Date, loading: Bool, formatter: CopyLineFormatter,
            hidden: [BlockType] = [], timeFormat: TimeFormat = .value24,
            openTrip: @escaping (String) -> Void, openStep: @escaping (String) -> Void,
            settings: @escaping () -> Void, pastTrips: @escaping () -> Void,
            refresh: @escaping () async -> Void
        ) {
            self.trips = trips
            self.detail = detail
            self.now = now
            self.loading = loading
            self.formatter = formatter
            self.hidden = hidden
            self.timeFormat = timeFormat
            self.openTrip = openTrip
            self.openStep = openStep
            self.settings = settings
            self.pastTrips = pastTrips
            self.refresh = refresh
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String, _ values: [String: String] = [:]) -> String {
            PlanStrings.text(key, language: language, values)
        }
        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: PlanUITokens.space6) {
                    if loading {
                        PlanLoadingView(label: t("Loading today"))
                    } else if trips.isEmpty {
                        empty
                    } else if let hero = selectTodayTrip(trips, now: now) {
                        let view = detail.map { todayView($0, marks: $0.checkState.marks, now: now, hidden: hidden) }
                        Group {
                            if hero.status == .upcoming {
                                TodayFutureTripCard(
                                    trip: hero, now: now, formatter: formatter, next: view?.nextStep,
                                    timeFormat: timeFormat
                                ) { openTrip(hero.card.id) }
                            } else {
                                TripSummaryCard(
                                    trip: hero, now: now, formatter: formatter, next: view?.nextStep,
                                    timeFormat: timeFormat
                                ) { openTrip(hero.card.id) }
                            }
                        }.accessibilityIdentifier("today.trip")
                        if hero.status == .upcoming { future(hero) } else if let view { panel(view) }
                    } else if let ended = lastEndedTrip(trips, now: now) {
                        completed(ended)
                    }
                }.planContentBounds().padding(PlanUITokens.space4).planPageRail()
            }
            .planPageSafeArea()
            .refreshable { await refresh() }
            .scrollBounceBehavior(.always, axes: .vertical)
            .background(ColorToken.background.color).foregroundStyle(ColorToken.foreground.color)
            .navigationTitle(t("Today")).accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.screen")
        }
        private var empty: some View {
            VStack(spacing: PlanUITokens.space3) {
                Image(systemName: "moon").font(.system(size: PlanUITokens.space6))
                    .frame(width: PlanUITokens.space14, height: PlanUITokens.space14)
                    .foregroundStyle(ColorToken.dawnText.color).background(ColorToken.muted.color, in: Circle())
                    .accessibilityHidden(true)
                Text(t("No trips yet")).planTextStyle(Typography.screenCardTitle).accessibilityAddTraits(.isHeader)
                Text(t("Add your flights and you get a day-by-day plan for sleep, light and caffeine."))
                    .foregroundStyle(ColorToken.mutedForeground.color)
            }.font(Typography.screenBodyLg.font).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .padding(.vertical, PlanUITokens.space8).planEmptyCard().accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.empty")
        }
        private func completed(_ trip: TripListValue) -> some View {
            let endDate = min(
                trip.planEndDate ?? String(trip.card.arriveLocal.prefix(10)),
                localDate(now.ISO8601Format(), zone: TimeZone.current.identifier))
            return VStack(spacing: PlanUITokens.space3) {
                Image(systemName: "checkmark.circle").font(.system(size: PlanUITokens.space6))
                    .frame(width: PlanUITokens.space14, height: PlanUITokens.space14)
                    .foregroundStyle(ColorToken.dawnText.color).background(ColorToken.muted.color, in: Circle())
                    .accessibilityHidden(true)
                Text(t("No trips coming up")).planTextStyle(Typography.screenCardTitle).accessibilityAddTraits(
                    .isHeader)
                Text(
                    t(
                        "Your last trip, {{route}}, ended on {{date}}. Plan the next one when you know your flights.",
                        [
                            "route":
                                "\(trip.card.from.city ?? trip.card.from.iata) → \(trip.card.to.city ?? trip.card.to.iata)",
                            "date": endDate.prefix(4)
                                == localDate(now.ISO8601Format(), zone: TimeZone.current.identifier).prefix(4)
                                ? formatter.formatDayMonth(endDate, language: language)
                                : formatter.formatDate(endDate, language: language),
                        ]))
                Button(t("See past trips"), action: pastTrips).buttonStyle(.bordered)
                    .accessibilityIdentifier("today.past")
            }.font(Typography.screenBodyLg.font).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .planCard().accessibilityIdentifier("today.completed")
        }
        private func future(_ trip: TripListValue) -> some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                Text(t("Nothing to do today")).planTextStyle(Typography.screenSectionTitle).accessibilityAddTraits(
                    .isHeader)
                Text(t("Keep your usual sleep times."))
                if let days = trip.preparationDays, days > 0 {
                    Text(
                        PlanStrings.text(
                            "Your {{count}} preparation days start on {{date}}.", language: language,
                            [
                                "date": formatter.formatWeekdayDate(
                                    trip.planStartUtc ?? trip.card.departureUtc, language: language,
                                    zone: trip.planStartZone ?? trip.card.from.zone)
                            ], count: days))
                }
            }.font(Typography.screenBody.font).planCard().accessibilityIdentifier("today.future")
        }
        @ViewBuilder private func panel(_ view: TodayPlan) -> some View {
            if let day = view.currentDay {
                HStack {
                    Text(
                        formatter.catalog.text(
                            dayLabelKey(day.labelPhase) ?? "", language: language,
                            arguments: ["count": String(day.postArrivalIndex ?? 0)],
                            count: Double(day.postArrivalIndex ?? 0))
                    )
                    .planTextStyle(Typography.screenSectionTitle).accessibilityAddTraits(.isHeader)
                    if let status = day.status {
                        DayStatusPill(status: status, text: t(dayStatusLabelKey(status) ?? ""))
                    }
                }
                if let progress = view.dayProgress, progress.total > 0 {
                    DayProgressRow(
                        done: progress.done, total: progress.total, skipped: progress.skipped, language: language)
                }
            }
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                heading("Right now")
                if view.currentSteps.isEmpty {
                    VStack(spacing: PlanUITokens.space2) {
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: PlanUITokens.space6))
                            .accessibilityHidden(true)
                        Text(t("Nothing scheduled right now.")).planTextStyle(
                            Typography.screenBodyLg, color: .mutedForeground)
                    }.foregroundStyle(ColorToken.mutedForeground.color).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(PlanUITokens.space6)
                        .overlay {
                            RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).strokeBorder(
                                ColorToken.border.color,
                                style: StrokeStyle(lineWidth: AuthTokens.borderWidth, dash: [PlanUITokens.space1]))
                        }
                }
                ForEach(view.currentSteps, id: \.id) { row($0, view: view, running: true) }
            }
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                heading("Up next")
                if view.upcomingSteps.isEmpty {
                    Text(t("No more scheduled items.")).planTextStyle(Typography.screenBodyLg)
                }
                ForEach(view.upcomingSteps, id: \.id) { row($0, view: view, running: false) }
            }
            if view.importantHidden || view.allCategoriesHidden {
                Button(action: settings) {
                    HStack(spacing: PlanUITokens.space3) {
                        Image(systemName: "eye.slash").accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(
                                t(
                                    view.allCategoriesHidden
                                        ? "All categories are hidden." : "Some important steps are hidden."))
                            Text(t("Show them in Settings › Preferences")).foregroundStyle(
                                ColorToken.mutedForeground.color)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(ColorToken.mutedForeground.color)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, PlanUITokens.space2).padding(.horizontal, PlanUITokens.space3)
                    .frame(minHeight: PlanUITokens.space14)
                    .background(ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusXl))
                }.buttonStyle(.plain).font(Typography.screenBody.font).accessibilityIdentifier(
                    "today.hidden")
            }
        }
        private func heading(_ key: String) -> some View {
            Text(t(key).uppercased()).planTextStyle(Typography.screenLabel, color: .mutedForeground)
                .accessibilityAddTraits(.isHeader)
        }
        private func row(_ block: BlockView, view: TodayPlan, running: Bool) -> some View {
            let mark =
                block.actionable
                ? block.checkKey.flatMap { key in view.marks.first { checkIdentity($0.key) == checkIdentity(key) } }
                : nil
            return TodayStepRow(
                block: block, mark: mark, now: now, formatter: formatter, trip: detail?.trip,
                timeFormat: timeFormat, running: running
            ) { openStep(block.id) }
        }
    }

    public struct PlanLoadingView: View {
        public let label: String
        public init(label: String) { self.label = label }
        public var body: some View {
            VStack(spacing: PlanUITokens.space4) {
                RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl).fill(ColorToken.muted.color)
                    .frame(height: PlanUITokens.space1 * 62)
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl).fill(ColorToken.muted.color).frame(
                        height: PlanUITokens.space16)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityIdentifier("plan.loading")
        }
    }
#endif

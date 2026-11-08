#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct TripSummaryCard: View {
        @Environment(\.locale) private var locale
        public let trip: TripListValue
        public let now: Date
        public let formatter: CopyLineFormatter
        public var next: BlockView?
        public var showPlanStart: Bool
        public var timeFormat: TimeFormat
        public var open: () -> Void
        public init(
            trip: TripListValue, now: Date, formatter: CopyLineFormatter, next: BlockView? = nil,
            timeFormat: TimeFormat = .value24, showPlanStart: Bool = true, open: @escaping () -> Void
        ) {
            self.trip = trip
            self.now = now
            self.formatter = formatter
            self.next = next
            self.showPlanStart = showPlanStart
            self.timeFormat = timeFormat
            self.open = open
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String, _ values: [String: String] = [:]) -> String {
            PlanStrings.text(key, language: language, values)
        }
        public var body: some View {
            let card = trip.card
            Button(action: open) {
                VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                    HStack {
                        PlanBadge(
                            text: t(
                                trip.status == .active ? "Active" : trip.status == .completed ? "Completed" : "Upcoming"
                            ), active: trip.status == .active)
                        if let number = card.flightNumber { Text(number).font(Typography.screenMeta.font) }
                        Spacer(minLength: 0)
                        Text(formatter.formatOffset(Double(card.offsetDifferenceMinutes), language: language))
                            .font(Typography.screenMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
                    }
                    HStack(spacing: PlanUITokens.space3) {
                        airport(card.from)
                        Spacer(minLength: 0)
                        Image(systemName: "airplane").accessibilityHidden(true)
                        Spacer(minLength: 0)
                        airport(card.to, trailing: true)
                    }
                    HStack(spacing: PlanUITokens.space2) {
                        Text(times).font(Typography.screenBody.font).monospacedDigit()
                        if next == nil {
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: PlanUITokens.space5))
                                .accessibilityHidden(true)
                        }
                    }.foregroundStyle(ColorToken.mutedForeground.color)
                    if let next {
                        HStack(spacing: PlanUITokens.space3) {
                            CategorySwatch(next.type)
                            VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                                Text(nextLabel(next)).font(Typography.screenEyebrow.font).foregroundStyle(
                                    ColorToken.dawnText.color)
                                Text(
                                    formatter.format(
                                        next.text,
                                        options: CopyFormat(
                                            language: language, timeFormat: timeFormat, displayZone: next.displayTz))
                                )
                                .font(Typography.screenBodyLg.font)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.padding(PlanUITokens.space3).background(
                            ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl))
                    } else if showPlanStart && trip.status == .upcoming {
                        Text(startLabel).font(Typography.screenLabel.font).foregroundStyle(ColorToken.dawnText.color)
                    }
                }.planCard(active: trip.status == .active, completed: trip.status == .completed)
            }
            .buttonStyle(.plain).foregroundStyle(ColorToken.cardForeground.color)
            .accessibilityIdentifier("trip.\(card.id)").accessibilityElement(children: .combine)
        }
        private func airport(_ airport: AirportRef, trailing: Bool = false) -> some View {
            VStack(alignment: trailing ? .trailing : .leading) {
                Text(airport.iata).font(Typography.screenPageTitle.font)
                if let city = airport.city {
                    Text(city).font(Typography.screenBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                }
            }.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        }
        private var times: String {
            let card = trip.card
            let options = CopyFormat(language: language, timeFormat: timeFormat)
            return formatter.formatDayMonth(card.departureUtc, language: language, zone: card.from.zone) + " "
                + formatter.formatInstant(card.departureUtc, options: options, zone: card.from.zone) + " → "
                + formatter.formatDayMonth(card.arrivalUtc, language: language, zone: card.to.zone) + " "
                + formatter.formatInstant(card.arrivalUtc, options: options, zone: card.to.zone)
        }
        private var startLabel: String {
            let start = trip.planStartUtc ?? trip.card.departureUtc
            let zone = trip.planStartZone ?? trip.card.from.zone
            let days = calendarDaysUntil(start, now: now, zone: zone)
            if days == 0 { return t("Plan starts today") }
            if days == 1 { return t("Plan starts tomorrow") }
            return t(
                "Plan starts on {{date}}", ["date": formatter.formatWeekdayDate(start, language: language, zone: zone)])
        }
        private func nextLabel(_ block: BlockView) -> String {
            if planDate(block.startUtc) <= now { return t("Next · now") }
            let duration = formatter.formatMinutes(
                max(0, ceil(planDate(block.startUtc).timeIntervalSince(now) / 60)), language: language, duration: true)
            return t("Next · in {{duration}}", ["duration": duration])
        }
    }
#endif

#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    struct TodayFutureTripCard: View {
        @Environment(\.locale) private var locale
        let trip: TripListValue
        let now: Date
        let formatter: CopyLineFormatter
        let next: BlockView?
        let timeFormat: TimeFormat
        let open: () -> Void

        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String, _ values: [String: String] = [:], count: Int? = nil) -> String {
            PlanStrings.text(key, language: language, values, count: count)
        }
        var body: some View {
            let card = trip.card
            let days = calendarDaysUntil(card.departureUtc, now: now, zone: card.from.zone)
            Button(action: open) {
                VStack(alignment: .leading, spacing: PlanUITokens.futureCardSpacing) {
                    HStack {
                        PlanBadge(text: t("Upcoming"))
                        Spacer(minLength: 0)
                        Text(days == 0 ? t("Today") : t("In {{count}} days", count: days))
                            .planTextStyle(Typography.screenMeta, color: .mutedForeground)
                    }
                    Text(t("{{from}} → {{to}}", ["from": card.from.iata, "to": card.to.iata]))
                        .planTextStyle(Typography.screenPageTitle)
                    Text(
                        t(
                            card.flightNumber == nil
                                ? "{{date}} · {{offset}}" : "{{date}} · {{flightNumber}} · {{offset}}",
                            [
                                "date": formatter.formatWeekdayDate(
                                    card.departureUtc, language: language, zone: card.from.zone),
                                "flightNumber": card.flightNumber ?? "",
                                "offset": formatter.formatOffset(
                                    Double(card.offsetDifferenceMinutes), language: language),
                            ])
                    )
                    .planTextStyle(Typography.screenBody, color: .mutedForeground)
                    if let next {
                        HStack(spacing: PlanUITokens.space3) {
                            CategorySwatch(next.type)
                            VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                                Text(startLabel).planTextStyle(Typography.screenEyebrow, color: .dawnText)
                                Text(
                                    formatter.format(next.text, options: options(next))
                                        + t(
                                            " · {{time}}",
                                            ["time": formatter.formatInstant(next.startUtc, options: options(next))])
                                )
                                .font(Typography.screenBodyLg.font.weight(.medium))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: PlanUITokens.space5))
                                .foregroundStyle(ColorToken.mutedForeground.color).accessibilityHidden(true)
                        }.padding(PlanUITokens.space3)
                            .background(
                                ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl))
                    }
                }.planCard().contentShape(RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl))
            }.buttonStyle(.plain).foregroundStyle(ColorToken.cardForeground.color)
                .accessibilityIdentifier("trip.\(card.id)").accessibilityElement(children: .combine)
        }
        private func options(_ block: BlockView) -> CopyFormat {
            CopyFormat(language: language, timeFormat: timeFormat, displayZone: block.displayTz)
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
    }
#endif

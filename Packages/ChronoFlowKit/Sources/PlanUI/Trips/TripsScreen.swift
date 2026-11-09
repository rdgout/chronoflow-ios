#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct TripsScreen: View {
        @Environment(\.locale) private var locale
        public let trips: [TripListValue]
        public let details: [String: TripDetail]
        public let now: Date
        public let loading: Bool
        public let formatter: CopyLineFormatter
        public var timeFormat: TimeFormat
        public var hidden: [BlockType]
        public var open: (String) -> Void
        public var create: (() -> Void)?

        public init(
            trips: [TripListValue], details: [String: TripDetail], now: Date, loading: Bool,
            formatter: CopyLineFormatter, timeFormat: TimeFormat = .value24, hidden: [BlockType] = [],
            open: @escaping (String) -> Void, create: (() -> Void)? = nil
        ) {
            self.trips = trips
            self.details = details
            self.now = now
            self.loading = loading
            self.formatter = formatter
            self.timeFormat = timeFormat
            self.hidden = hidden
            self.open = open
            self.create = create
        }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { PlanStrings.text(key, language: language) }
        public var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PlanUITokens.space6) {
                    if loading {
                        TripsLoadingView()
                    } else if trips.isEmpty {
                        VStack(spacing: PlanUITokens.space3) {
                            Image(systemName: "airplane").font(.system(size: PlanUITokens.space6))
                                .frame(width: PlanUITokens.space14, height: PlanUITokens.space14)
                                .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                            Text(t("No trips yet")).planTextStyle(Typography.screenCardTitle).accessibilityAddTraits(
                                .isHeader)
                            Text(t("Your upcoming, active and past trips show up here."))
                                .planTextStyle(Typography.screenBodyLg, color: .mutedForeground)
                            if let create {
                                Button(t("Plan a trip"), action: create).buttonStyle(.borderedProminent)
                                    .foregroundStyle(ColorToken.primaryForeground.color)
                                    .buttonBorderShape(.capsule).accessibilityIdentifier("trips.create-empty")
                            }
                        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            .padding(.vertical, PlanUITokens.space8).planEmptyCard().accessibilityElement(
                                children: .contain
                            )
                            .accessibilityIdentifier(
                                "trips.empty")
                    } else {
                        ForEach(tripSections(trips), id: \.status.rawValue) { section in
                            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                                Text(
                                    t(
                                        section.status == .active
                                            ? "Active" : section.status == .upcoming ? "Upcoming" : "Completed"
                                    ).uppercased()
                                )
                                .planTextStyle(Typography.screenLabel, color: .mutedForeground)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("trips.section.\(section.status.rawValue)")
                                ForEach(section.trips, id: \.card.id) { trip in
                                    let next =
                                        trip.status == .active
                                        ? details[trip.card.id].flatMap {
                                            todayView($0, marks: $0.checkState.marks, now: now, hidden: hidden).nextStep
                                        } : nil
                                    TripSummaryCard(
                                        trip: trip, now: now, formatter: formatter, next: next,
                                        timeFormat: timeFormat, showPlanStart: false
                                    ) { open(trip.card.id) }
                                }
                            }
                        }
                    }
                }.planContentBounds().padding(PlanUITokens.space4).planPageRail().planRefreshContent()
            }
            .planRefreshScroll()
            .navigationTitle(t("My trips")).accessibilityElement(children: .contain)
            .accessibilityIdentifier("trips.screen")
            .toolbar {
                if let create {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: create) { Image(systemName: "plus") }
                            .accessibilityLabel(t("New trip")).accessibilityIdentifier("trips.create")
                    }
                }
            }
            .background(ColorToken.background.color).foregroundStyle(ColorToken.foreground.color)
        }
    }
#endif

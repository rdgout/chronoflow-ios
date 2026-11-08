import AppCore
import DesignSystem
import LocalStore
import PlanCore
import SwiftUI
import Sync

public struct TripPageView: View {
    @State private var model: TripPageModel
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var formatter: CopyLineFormatter?
    @State private var frames: [String: CGRect] = [:]
    @State private var viewport = CGSize.zero
    @State private var showLegend = false
    public var onBlock: (String) -> Void = { _ in }
    public var onActions: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onMakePlan: (() -> Void)?
    public var onTrips: (() -> Void)?
    public var onToday: (() -> Void)?
    public var onFirstTimelineFrame: () -> Void = {}

    public init(model: TripPageModel) { _model = State(initialValue: model) }
    public init(
        tripID: String, repository: TripRepository, retention: PlanRetention,
        dayID: String? = nil, blockID: String? = nil, keptDay: String? = nil, awaitingSync: Bool = false,
        fetchDetail: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.init(
            model: TripPageModel(
                tripID: tripID, repository: repository, retention: retention,
                dayID: dayID, blockID: blockID, keptDay: keptDay, awaitingSync: awaitingSync, fetchDetail: fetchDetail))
    }

    private var copy: PageCopy { PageCopy(language: model.plan.language) }
    public var body: some View {
        Group {
            if model.state == .notFound || model.state == .server { errorPage } else { page }
        }
        .foregroundStyle(ColorToken.foreground.color).background(ColorToken.background.color)
        .task {
            model.plan.language = locale.language.languageCode?.identifier == "nl" ? .nl : .en
            model.start()
            formatter = try? await CopyCatalog.load().mapFormatter()
        }
        .onChange(of: locale) { _, value in
            model.plan.language = value.language.languageCode?.identifier == "nl" ? .nl : .en
        }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showLegend) {
            NavigationStack {
                ScrollView { PriorityKey(copy: copy).padding(PlanMetrics.gutter) }
                    .navigationTitle(copy("Legend"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button(copy("Done")) { showLegend = false } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }

    private var page: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: PlanMetrics.sectionGap) {
                        if let prepared = model.plan.prepared, model.state == .ready {
                            summary(prepared)
                            DayNavigation(days: prepared.days, selected: model.anchor.dayID, copy: copy) {
                                jump($0, proxy: proxy)
                            }
                            ForEach(prepared.days) { day in
                                VStack(spacing: 0) {
                                    DayHeader(day: day, copy: copy)
                                    DayListView(day: day, onBlock: onBlock)
                                }.id(day.id)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: DayFrames.self,
                                                value: [day.id: geo.frame(in: .named("trip.scroll"))])
                                        })
                            }
                            EndOfPlanCard(plan: prepared, copy: copy) { jump($0, proxy: proxy) }
                            if !model.plan.hiddenCategories.isEmpty {
                                Button(copy("Some steps are hidden in your preferences.")) { onSettings?() }.disabled(
                                    onSettings == nil)
                            }
                        } else if model.state == .noPlan {
                            noPlan
                        } else {
                            if model.state == .remoteLoading || model.state == .remoteOffline { remoteSummary }
                            if model.state == .remoteOffline { remoteOffline } else { skeleton }
                        }
                    }.padding(.horizontal, PlanMetrics.gutter).padding(.bottom, PlanMetrics.gutter)
                }.coordinateSpace(name: "trip.scroll").accessibilityIdentifier("trip.scroll")
                    .onAppear { viewport = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewport = size }
                    .onPreferenceChange(DayFrames.self) { value in
                        frames = value
                        if let current = model.plan.prepared?.days.last(where: {
                            (value[$0.id]?.minY ?? .infinity) <= PlanMetrics.compactHeaderHeight
                        }), let frame = value[current.id] {
                            model.select(dayID: current.id, offset: max(0, -frame.minY))
                        }
                    }
                    .overlay(alignment: .top) { compactHeader }
                    .onChange(of: model.plan.prepared) { old, new in
                        guard new != nil else { return }
                        let previous = model.anchor
                        model.acceptPreparedPlan()
                        if old == nil || old?.days.map(\.id) != new?.days.map(\.id) {
                            let anchor =
                                old == nil
                                ? model.anchor : replacementAnchor(previous, days: model.plan.detail?.plan.days ?? [])
                            if let id = anchor.dayID {
                                let height = frames[previous.dayID ?? ""]?.height ?? viewport.height
                                let fraction = height > viewport.height ? anchor.offset / (height - viewport.height) : 0
                                proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: fraction))
                            }
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(model.plan.prepared?.days ?? []) { day in
                            Button {
                                jump(day.id, proxy: proxy)
                            } label: {
                                if day.id == model.anchor.dayID {
                                    Label(day.title + " · " + day.date, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: day.title + " · " + day.date)
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            Text(verbatim: model.plan.prepared?.title ?? cardTitle).font(Typography.planTitle.font)
                                .lineLimit(1)
                            HStack(spacing: PlanMetrics.smallGap) {
                                Text(verbatim: subtitle).lineLimit(1)
                                Image(systemName: "chevron.down")
                            }.font(Typography.planSubtitle.font).foregroundStyle(ColorToken.mutedForeground.color)
                        }
                    }.accessibilityLabel(copy("Go to day")).accessibilityIdentifier("trip.dayMenu")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(copy("Trip actions"), systemImage: "ellipsis") { onActions?() }.disabled(onActions == nil)
                }
            }
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var cardTitle: String {
        guard let card = model.plan.card else { return "" }
        return "\(card.from.city ?? card.from.iata) → \(card.to.city ?? card.to.iata)"
    }
    private var subtitle: String {
        if let id = model.anchor.dayID, let frame = frames[id], frame.minY < 0,
            let day = model.plan.prepared?.days.first(where: { $0.id == id })
        {
            return day.title + " · " + day.date
        }
        return model.plan.prepared?.subtitle ?? ""
    }

    @ViewBuilder private var compactHeader: some View {
        if let id = model.anchor.dayID, let frame = frames[id],
            let day = model.plan.prepared?.days.first(where: { $0.id == id })
        {
            let distance = -frame.minY
            let opacity =
                reduceMotion
                ? (distance >= PlanMetrics.compactHeaderHeight ? 1.0 : 0)
                : min(1, max(0, distance / PlanMetrics.compactFadeDistance))
            HStack {
                Text(verbatim: day.title + " · " + day.date).font(Typography.planListLine.font)
                Spacer(minLength: PlanMetrics.smallGap)
                Text(verbatim: day.zone).font(Typography.planSubtitle.font)
            }.padding(.horizontal, PlanMetrics.gutter).frame(minHeight: PlanMetrics.compactHeaderHeight)
                .background(ColorToken.card.color).opacity(opacity).accessibilityHidden(opacity < 1)
        }
    }

    private func jump(_ id: String, proxy: ScrollViewProxy) {
        model.select(dayID: id)
        if reduceMotion { proxy.scrollTo(id, anchor: .top) } else { withAnimation { proxy.scrollTo(id, anchor: .top) } }
    }

    private func summary(_ prepared: PreparedPlan) -> some View {
        PlanCard {
            VStack(alignment: .leading, spacing: PlanMetrics.sectionGap) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                        Text(verbatim: copy("Your plan")).font(Typography.eyebrow.font).foregroundStyle(
                            ColorToken.dawnText.color)
                        if let rationale = prepared.rationale {
                            Text(verbatim: rationale).font(Typography.welcomeWordmark.font)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(copy("Legend: what the colours and patterns mean"), systemImage: "info.circle") {
                        showLegend = true
                    }
                    .labelStyle(.iconOnly).frame(minWidth: PlanMetrics.touch, minHeight: PlanMetrics.touch)
                }
                Text(verbatim: prepared.summary).font(Typography.planListLine.font).foregroundStyle(
                    ColorToken.mutedForeground.color)
                if let detail = model.plan.detail, let formatter {
                    DualClocks(
                        trip: detail.trip, now: model.plan.now, formatter: formatter,
                        options: CopyFormat(language: model.plan.language, timeFormat: model.plan.timeFormat),
                        activeZone: detail.plan.days.flatMap(\.zones).first {
                            planDate($0.startUtc) <= model.plan.now && model.plan.now < planDate($0.endUtc)
                        }?.tz)
                }
            }
        }.accessibilityLabel(copy("Plan summary"))
    }

    private var remoteSummary: some View {
        PlanCard { Text(verbatim: cardTitle).font(Typography.welcomeWordmark.font) }
    }
    private var skeleton: some View {
        VStack(spacing: PlanMetrics.sectionGap) {
            if model.state == .remoteLoading {
                Text(verbatim: copy("Downloading this trip’s plan…")).font(Typography.authHint.font)
            }
            RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).fill(ColorToken.muted.color).frame(
                height: PlanMetrics.skeletonSummary)
            Capsule().fill(ColorToken.muted.color).frame(height: PlanMetrics.touch)
            RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).fill(ColorToken.muted.color).frame(
                height: PlanMetrics.skeletonTimeline)
        }.accessibilityElement(children: .ignore).accessibilityLabel(copy("Loading your plan"))
    }
    private var noPlan: some View {
        stateCard(
            icon: "calendar", title: "No plan yet",
            text:
                "Your flights are saved. Check your answers to make the plan. Once it’s made, it’s stored on this phone and works offline."
        ) {
            Button(copy("Check answers and make plan")) { onMakePlan?() }.buttonStyle(.borderedProminent).disabled(
                onMakePlan == nil)
            Text(verbatim: copy("Making the plan needs a connection.")).font(Typography.planListLine.font)
        }
    }
    private var remoteOffline: some View {
        stateCard(
            icon: "icloud.and.arrow.down", title: "This plan downloads when you’re online",
            text:
                "Plans for active trips and trips in the next 7 days are always on your phone. This one is further away, so its plan opens once you’re connected."
        ) {
            Button(copy("Try again")) { model.retry() }.buttonStyle(.bordered)
            Text(verbatim: copy("Your other trips keep working offline.")).font(Typography.planListLine.font)
        }
    }
    private func stateCard<Actions: View>(
        icon: String, title: String, text: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: PlanMetrics.sectionGap) {
            Image(systemName: icon).frame(width: PlanMetrics.touch, height: PlanMetrics.touch).background(
                ColorToken.muted.color, in: Circle())
            Text(verbatim: copy(title)).font(Typography.welcomeWordmark.font).accessibilityAddTraits(.isHeader)
            Text(verbatim: copy(text)).font(Typography.authBody.font).foregroundStyle(ColorToken.mutedForeground.color)
            actions()
        }.padding(PlanMetrics.cardPadding).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            .overlay(
                RoundedRectangle(cornerRadius: PlanMetrics.cardRadius).strokeBorder(
                    ColorToken.border.color,
                    style: StrokeStyle(lineWidth: PlanMetrics.border, dash: [PlanMetrics.smallGap])))
    }
    private var errorPage: some View {
        let missing = model.state == .notFound
        return VStack(spacing: PlanMetrics.sectionGap) {
            Spacer()
            Text(verbatim: copy(missing ? "Not found" : "Something went wrong")).font(Typography.eyebrow.font)
            Text(verbatim: copy(missing ? "We can’t find that" : "We’re having trouble")).font(
                Typography.authHeading.font)
            Text(
                verbatim: copy(
                    missing
                        ? "The link may be old, or the trip was deleted."
                        : "It’s on our side, not yours, and your plans are safe. Try again in a few minutes.")
            ).font(Typography.authBody.font)
            Spacer()
            Button(copy(missing ? "Go to my trips" : "Try again")) { if missing { onTrips?() } else { model.retry() } }
                .buttonStyle(.borderedProminent)
            Button(copy(missing ? "Open Today" : "Open my plan for today")) { onToday?() }.disabled(onToday == nil)
        }.padding(PlanMetrics.gutter).multilineTextAlignment(.center).foregroundStyle(ColorToken.skyTitle.color)
            .background { CfSky() }
    }
}

private struct DayFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension CopyCatalog {
    nonisolated fileprivate func mapFormatter() -> CopyLineFormatter { CopyLineFormatter(catalog: self) }
}

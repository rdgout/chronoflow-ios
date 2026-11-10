import AppCore
import DesignSystem
import LocalStore
import PlanCore
import SwiftUI
import Sync

public struct TripPageView: View {
    @State private var model: TripPageModel
    @Environment(\.locale) private var locale
    #if DEBUG
        @Environment(\.planUITestOptions) private var uiTestOptions
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var formatter: CopyLineFormatter?
    @State private var scroll = TripScrollTracker()
    @State private var headerScrolled = false
    @State private var copy: PageCopy
    @State private var windowSize: CGSize?
    @ScaledMetric(relativeTo: .caption2) private var compactHeight = PlanMetrics.compactHeaderHeight
    @State private var compactHeaderBottom: CGFloat = 0
    @State private var showLegend = false
    @State private var renderer = TimelineRenderer()
    @State private var timelineSymbols = TimelineSymbols()
    @State private var feedback = RefreshFeedbackModel()
    public var refresh: () async throws -> SyncResult?
    public var onActions: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onMakePlan: (() -> Void)?
    public var onTrips: (() -> Void)?
    public var onToday: (() -> Void)?
    public var onFirstTimelineFrame: () -> Void = {}

    public init(
        model: TripPageModel, formatter: CopyLineFormatter? = nil,
        refresh: @escaping () async throws -> SyncResult?
    ) {
        _model = State(initialValue: model)
        _copy = State(initialValue: PageCopy(language: model.plan.language))
        _formatter = State(initialValue: formatter)
        self.refresh = refresh
    }
    public init(
        tripID: String, repository: TripRepository, retention: PlanRetention,
        dayID: String? = nil, blockID: String? = nil, keptDay: String? = nil, awaitingSync: Bool = false,
        timeFormat: TimeFormat = .value24, hiddenCategories: [BlockType] = [],
        fetchDetail: @escaping @Sendable (String) async throws -> Void = { _ in },
        refresh: @escaping () async throws -> SyncResult?
    ) {
        self.init(
            model: TripPageModel(
                tripID: tripID, repository: repository, retention: retention,
                dayID: dayID, blockID: blockID, keptDay: keptDay, awaitingSync: awaitingSync,
                timeFormat: timeFormat, hiddenCategories: hiddenCategories, fetchDetail: fetchDetail), refresh: refresh)
    }

    public var body: some View {
        @Bindable var model = model
        ZStack {
            if model.state == .notFound || model.state == .server {
                GeometryReader { geometry in
                    ScrollView {
                        errorPage.frame(minHeight: geometry.size.height)
                    }
                    .refreshable { await refreshPlan() }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("trip.scroll")
                }
            } else {
                page
            }
        }
        .planRefreshFeedback(feedback)
        .foregroundStyle(ColorToken.foreground.color).background(ColorToken.background.color)
        #if os(iOS)
            .background { TripWindowSizeHost { windowSize = $0 } }
        #endif
        .task {
            model.plan.language = locale.language.languageCode?.identifier == "nl" ? .nl : .en
            copy = PageCopy(language: model.plan.language)
            model.start()
            if formatter == nil { formatter = try? await CopyCatalog.load().mapFormatter() }
        }
        .onChange(of: locale) { _, value in
            model.plan.language = value.language.languageCode?.identifier == "nl" ? .nl : .en
            copy = PageCopy(language: model.plan.language)
        }
        .onDisappear { model.stop() }
        #if canImport(UIKit)
            .sheet(item: $model.selectedStep) { selection in
                TripPageStepSheet(model: model, selection: selection)
            }
        #endif
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

    private func refreshPlan() async {
        await feedback.refresh(action: refresh)
    }

    private var page: some View {
        GeometryReader { geometry in
            let containerSize = CGSize(
                width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
            let size = windowSize ?? containerSize
            let layout = TripPageLayout.resolve(width: size.width, height: size.height)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: PlanMetrics.sectionGap) {
                        if model.state != .ready && !model.plan.metadata.isEmpty {
                            Text(verbatim: model.plan.metadata).font(Typography.planSubtitle.font)
                                .foregroundStyle(ColorToken.mutedForeground.color).frame(maxWidth: .infinity)
                        }
                        if let prepared = model.plan.prepared, model.state == .ready, formatter != nil {
                            summary(prepared)
                            DayNavigation(days: prepared.days, selected: model.anchor.dayID, copy: copy) {
                                jump($0, proxy: proxy)
                            }
                            ForEach(prepared.days) { day in
                                TripDayRow(
                                    day: day, layout: model.plan.layouts[day.id],
                                    clock: model.plan.dayClock(for: day.id),
                                    timeline: model.timeline, copy: copy, renderer: renderer, symbols: timelineSymbols,
                                    compact: size.width < PlanMetrics.timelineLabelBreakpoint,
                                    listWidth: layout.listWidth, selectedBlockID: model.selectedStep?.blockID,
                                    stickyTop: max(compactHeight, compactHeaderBottom),
                                    viewportHeight: geometry.size.height, onBlock: openBlock,
                                    onFrame: onFirstTimelineFrame
                                ).equatable().id(day.id)
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
                            if model.state == .remoteOffline {
                                remoteOffline(wide: layout.isWide)
                            } else if model.state == .remoteLoading, let listWidth = layout.listWidth {
                                WidePlanSkeleton(copy: copy, listWidth: listWidth)
                            } else {
                                skeleton
                            }
                        }
                    }
                    .background {
                        #if os(iOS)
                            TripScrollHost(tracker: scroll)
                        #endif
                    }
                    .padding(.horizontal, layout.gutter).padding(.bottom, PlanMetrics.gutter).planPageRail()
                }
                .refreshable { await refreshPlan() }
                .scrollBounceBehavior(.always, axes: .vertical)
                .coordinateSpace(name: "trip.scroll").accessibilityElement(children: .contain)
                .accessibilityIdentifier("trip.scroll")
                .onAppear {
                    if model.plan.prepared != nil {
                        model.acceptPreparedPlan()
                        #if DEBUG
                            if uiTestOptions.startAtSummary { return }
                        #endif
                        if let id = model.anchor.dayID { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .onPreferenceChange(DayFrames.self) { value in
                    if scroll.resize(
                        frames: value, viewport: geometry.size, layout: layout, anchor: model.currentAnchor)
                    {
                        if let id = scroll.pendingDayID { proxy.scrollTo(id, anchor: .top) }
                        return
                    }
                    if let current = model.plan.prepared?.days.last(where: {
                        (value[$0.id]?.minY ?? .infinity) <= compactHeight
                    }), let frame = value[current.id] {
                        model.select(dayID: current.id, offset: max(0, -frame.minY))
                    }
                    let id = model.anchor.dayID ?? ""
                    let scrolled = (value[id]?.minY ?? .infinity) < 0
                    if headerScrolled != scrolled { headerScrolled = scrolled }
                    scroll.track(model.currentAnchor)
                    scroll.updateChrome(dayID: id, reduceMotion: reduceMotion)
                }
                .overlay(alignment: .top) { compactHeader(layout: layout) }
                .coordinateSpace(name: "trip.viewport")
                .onChange(of: model.plan.prepared) { old, new in
                    guard new != nil else { return }
                    let previous = model.currentAnchor
                    model.acceptPreparedPlan()
                    #if DEBUG
                        if old == nil, uiTestOptions.startAtSummary { return }
                    #endif
                    if old == nil || old?.revision != new?.revision || old?.days.map(\.id) != new?.days.map(\.id) {
                        let anchor =
                            old == nil
                            ? model.anchor : replacementAnchor(previous, days: model.plan.detail?.plan.days ?? [])
                        if let id = anchor.dayID {
                            let height = scroll.frames[previous.dayID ?? ""]?.height ?? geometry.size.height
                            let fraction =
                                height > geometry.size.height
                                ? anchor.offset / (height - geometry.size.height) : 0
                            proxy.scrollTo(id, anchor: UnitPoint(x: 0, y: fraction))
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if model.state == .ready, let prepared = model.plan.prepared {
                            Menu {
                                Section(copy("Go to a day")) {
                                    ForEach(Array(prepared.days.enumerated()), id: \.element.id) { index, day in
                                        Button {
                                            jump(day.id, proxy: proxy)
                                        } label: {
                                            if day.id == model.anchor.dayID {
                                                Label(day.title + " · " + day.date, systemImage: "checkmark")
                                            } else {
                                                Text(verbatim: day.title + " · " + day.date)
                                            }
                                        }
                                        .accessibilityIdentifier("trip.dayMenu.day.\(index)")
                                    }
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    Text(verbatim: prepared.title).font(Typography.planTitle.font).lineLimit(1)
                                    HStack(spacing: PlanMetrics.smallGap) {
                                        Text(verbatim: subtitle).lineLimit(1)
                                        Image(systemName: "chevron.down")
                                    }.font(Typography.planSubtitle.font).foregroundStyle(
                                        ColorToken.mutedForeground.color)
                                }
                            }.accessibilityLabel(dayMenuLabel).accessibilityValue(
                                Text(
                                    verbatim: model.plan.prepared?.days.first { $0.id == model.anchor.dayID }.map {
                                        $0.title + " · " + $0.date
                                    } ?? "")
                            ).accessibilityIdentifier("trip.dayMenu")
                                .planContentBounds(identifier: "trip.dayMenu")
                        } else {
                            Text(verbatim: model.plan.prepared?.title ?? cardTitle).font(Typography.planTitle.font)
                                .lineLimit(1)
                        }
                    }
                    if !layout.isWide && model.state == .ready && model.plan.prepared != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(
                                copy(model.timeline ? "Show as list" : "Show as timeline"),
                                systemImage: model.timeline ? "list.bullet" : "rectangle.split.3x1"
                            ) {
                                model.timeline.toggle()
                                if let id = model.anchor.dayID { proxy.scrollTo(id, anchor: .top) }
                            }.accessibilityIdentifier("trip.viewToggle")
                                .planContentBounds(identifier: "trip.viewToggle")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(copy("Trip actions"), systemImage: "ellipsis") { onActions?() }.disabled(
                            onActions == nil
                        )
                        .accessibilityIdentifier("trip.actions.open")
                    }
                }
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
    }

    private var cardTitle: String {
        guard let card = model.plan.card else { return "" }
        return "\(card.from.city ?? card.from.iata) → \(card.to.city ?? card.to.iata)"
    }
    private var dayMenuLabel: String {
        guard let trip = model.plan.detail?.trip, let prepared = model.plan.prepared else { return cardTitle }
        let from = trip.from.city ?? trip.from.iata
        let to = trip.to.city ?? trip.to.iata
        if headerScrolled, let day = prepared.days.first(where: { $0.id == model.anchor.dayID }) {
            return copy("%@ to %@, %@, %@. Go to a day", from, to, day.title, day.date)
        }
        return copy("%@ to %@, %@. Go to a day", from, to, prepared.spokenDates)
    }

    private var subtitle: String {
        if headerScrolled, let day = model.plan.prepared?.days.first(where: { $0.id == model.anchor.dayID }) {
            return day.title + " · " + day.date
        }
        return model.plan.prepared?.subtitle ?? ""
    }

    @ViewBuilder private func compactHeader(layout: TripPageLayout) -> some View {
        if let day = model.plan.prepared?.days.first(where: { $0.id == model.anchor.dayID }) {
            let header = Group {
                if layout.isWide {
                    VStack(spacing: PlanMetrics.smallGap) {
                        compactDayTitle(day)
                        HStack(spacing: PlanMetrics.wideColumnGap) {
                            LaneHeadings(copy: copy)
                            Color.clear.frame(width: layout.listWidth.map { CGFloat($0) }, height: 0)
                        }
                    }
                } else if model.timeline {
                    LaneHeadings(copy: copy, day: day)
                } else {
                    compactDayTitle(day)
                }
            }.padding(.horizontal, layout.gutter).frame(maxWidth: .infinity, minHeight: compactHeight)
                .background(ColorToken.card.color)
            #if os(iOS)
                CompactHeaderHost(content: header, tracker: scroll)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named("trip.viewport")).maxY
                    } action: {
                        compactHeaderBottom = $0
                    }
                    .planContentBounds(identifier: "trip.compactHeader")
            #else
                header.opacity(headerScrolled ? 1 : 0).accessibilityHidden(!headerScrolled)
            #endif
        }
    }

    private func compactDayTitle(_ day: PreparedDay) -> some View {
        HStack {
            (Text(verbatim: day.title).font(Typography.planListTitle.font)
                + Text(verbatim: " · " + day.date).font(Typography.planListLine.font)
                .foregroundColor(ColorToken.mutedForeground.color))
            Spacer(minLength: PlanMetrics.smallGap)
            Text(verbatim: day.zone).font(Typography.planSubtitle.font)
        }
    }

    private func jump(_ id: String, proxy: ScrollViewProxy) {
        model.select(dayID: id)
        if reduceMotion { proxy.scrollTo(id, anchor: .top) } else { withAnimation { proxy.scrollTo(id, anchor: .top) } }
    }

    private func openBlock(_ id: String) {
        guard let formatter else { return }
        model.selectBlock(id, formatter: formatter)
    }

    private func summary(_ prepared: PreparedPlan) -> some View {
        PlanCard {
            VStack(alignment: .leading, spacing: PlanMetrics.sectionGap) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                        Text(verbatim: copy("Your plan")).font(Typography.eyebrow.font).foregroundStyle(
                            ColorToken.dawnText.color)
                        if let rationale = prepared.shift {
                            Text(verbatim: rationale).font(Typography.welcomeWordmark.font)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(copy("Legend: what the colours and patterns mean"), systemImage: "info.circle") {
                        showLegend = true
                    }
                    .labelStyle(.iconOnly).frame(minWidth: PlanMetrics.touch, minHeight: PlanMetrics.touch)
                    .accessibilityIdentifier("trip.legend")
                }
                Text(verbatim: prepared.summary).font(Typography.planListLine.font).foregroundStyle(
                    ColorToken.mutedForeground.color)
                if let detail = model.plan.detail, let formatter {
                    DualClocks(
                        from: detail.trip.from, to: detail.trip.to, now: model.plan.now, formatter: formatter,
                        options: CopyFormat(language: model.plan.language, timeFormat: model.plan.timeFormat),
                        activeZone: detail.plan.days.flatMap(\.zones).first {
                            planDate($0.startUtc) <= model.plan.now && model.plan.now < planDate($0.endUtc)
                        }?.tz)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(copy("Plan summary"))
            .accessibilityIdentifier("trip.summary")
    }

    private var remoteSummary: some View {
        PlanCard {
            VStack(alignment: .leading, spacing: PlanMetrics.sectionGap) {
                Text(verbatim: copy("Your plan")).font(Typography.eyebrow.font).foregroundStyle(
                    ColorToken.dawnText.color)
                if let adaptation = model.plan.adaptation, let formatter {
                    Text(
                        verbatim: clockShiftText(
                            adaptation, formatter: formatter, options: CopyFormat(language: model.plan.language))
                    ).font(Typography.welcomeWordmark.font)
                }
                if let card = model.plan.card, let formatter {
                    DualClocks(
                        from: card.from, to: card.to, now: model.plan.now, formatter: formatter,
                        options: CopyFormat(language: model.plan.language, timeFormat: model.plan.timeFormat),
                        activeZone: nil, remote: true)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(copy("Plan summary"))
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
    private func remoteOffline(wide: Bool) -> some View {
        stateCard(
            icon: "icloud.and.arrow.down", title: "This plan downloads when you’re online",
            text:
                "Plans for active trips and trips in the next 7 days are always on your phone. This one is further away, so its plan opens once you’re connected.",
            wide: wide
        ) {
            Button(copy("Try again")) { model.retry() }.buttonStyle(.bordered)
            Text(verbatim: copy("Your other trips keep working offline.")).font(Typography.planListLine.font)
        }
        .padding(.top, wide ? PlanMetrics.sectionGap : 0)
        .planContentBounds(identifier: "trip.remote.offline")
    }
    private func stateCard<Actions: View>(
        icon: String, title: String, text: String, wide: Bool = false, @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: PlanMetrics.sectionGap) {
            Image(systemName: icon)
                .frame(
                    width: wide ? PlanMetrics.wideRemoteIcon : PlanMetrics.touch,
                    height: wide ? PlanMetrics.wideRemoteIcon : PlanMetrics.touch
                ).background(ColorToken.muted.color, in: Circle())
            Text(verbatim: copy(title)).font(
                title == "No plan yet" ? Typography.planCardTitle.font : Typography.planRemoteTitle.font
            ).accessibilityAddTraits(.isHeader)
            Text(verbatim: copy(text)).font(Typography.authBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                .frame(maxWidth: wide ? PlanMetrics.wideRemoteBodyWidth : .infinity)
            actions()
        }.padding(.horizontal, wide ? PlanMetrics.wideGutter : PlanMetrics.cardPadding)
            .padding(.vertical, wide ? PlanMetrics.wideRemotePadding : PlanMetrics.cardPadding).frame(
                maxWidth: .infinity
            ).multilineTextAlignment(.center)
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

struct DayFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension CopyCatalog {
    nonisolated fileprivate func mapFormatter() -> CopyLineFormatter { CopyLineFormatter(catalog: self) }
}

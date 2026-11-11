import DesignSystem
import Observation
import PlanCore
import SwiftUI

struct TripDayRow: View, Equatable {
    let day: PreparedDay
    let layout: DayLayout?
    let clock: DayClockState
    let timeline: Bool
    let copy: PageCopy
    let renderer: TimelineRenderer
    let symbols: TimelineSymbols
    var compact = false
    var listWidth: Double? = nil
    var selectedBlockID: String? = nil
    var stickyTop: Double = 0
    var scrollTracker: TripScrollTracker? = nil
    @State private var listHeight: CGFloat? = nil
    @State private var listTop: CGFloat = 0
    let viewportHeight: Double
    let onBlock: (String) -> Void
    let onFrame: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.layout == rhs.layout && lhs.clock === rhs.clock
            && lhs.timeline == rhs.timeline && lhs.copy == rhs.copy && lhs.renderer === rhs.renderer
            && lhs.symbols === rhs.symbols && lhs.viewportHeight == rhs.viewportHeight
            && lhs.compact == rhs.compact
            && lhs.listWidth == rhs.listWidth && lhs.selectedBlockID == rhs.selectedBlockID
            && lhs.stickyTop == rhs.stickyTop
            && lhs.scrollTracker === rhs.scrollTracker
    }

    var body: some View {
        VStack(spacing: 0) {
            DayHeader(day: day, copy: copy)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DayFrames.self,
                            value: ["header." + day.id: geo.frame(in: .named("trip.scroll"))])
                    })
            // Keep the timeline's gesture identity when the window crosses the wide breakpoint.
            HStack(alignment: .top, spacing: PlanMetrics.wideColumnGap) {
                VStack(spacing: 0) { clockContent }
                    .frame(maxWidth: .infinity)
                    .planContentBounds(identifier: listWidth == nil ? nil : "trip.wide.timeline.\(day.id)")
                if let listWidth, layout != nil {
                    GeometryReader { geometry in
                        let position = TripWideListPosition(
                            dayTop: listTop, dayHeight: geometry.size.height,
                            viewportHeight: viewportHeight, stickyTop: stickyTop,
                            contentHeight: listHeight ?? .infinity)
                        ScrollView {
                            DayListView(
                                day: day, now: clock.now, copy: copy, selectedBlockID: selectedBlockID,
                                onBlock: onBlock
                            )
                            .padding(.top, PlanMetrics.rowGap)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                listHeight = $0
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("trip.wide.list.scroll.\(day.id)")
                        .frame(height: position.height)
                        // Measure inside the transform so the frame follows the pinned viewport.
                        .planContentBounds(identifier: "trip.wide.list.\(day.id)")
                        .offset(y: position.offset)
                    }
                    .frame(width: listWidth)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named("trip.scroll")).minY
                    } action: {
                        listTop = $0
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DayFrames.self, value: [day.id: geo.frame(in: .named("trip.scroll"))])
            }
        )
        .background {
            #if os(iOS)
                if let scrollTracker { TripScrollHost(tracker: scrollTracker, dayID: day.id) }
            #endif
        }
        .planContentBounds(identifier: "trip.day.\(day.id)")
    }

    var clockContent: DayClockContent {
        DayClockContent(
            day: day, layout: layout, clock: clock, timeline: listWidth != nil || timeline, copy: copy,
            renderer: renderer, symbols: symbols, compact: compact, viewportHeight: viewportHeight,
            onBlock: onBlock, onFrame: onFrame)
    }
}

@Observable final class DayClockState {
    private(set) var now = Date.distantPast
    private(set) var text = ""

    func update(now: Date, text: String) {
        if self.now != now { self.now = now }
        if self.text != text { self.text = text }
    }
}

struct DayClockContent: View {
    let day: PreparedDay
    let layout: DayLayout?
    let clock: DayClockState
    let timeline: Bool
    let copy: PageCopy
    let renderer: TimelineRenderer
    let symbols: TimelineSymbols
    var compact = false
    let viewportHeight: Double
    let onBlock: (String) -> Void
    let onFrame: () -> Void

    var body: some View {
        if timeline, let layout {
            LaneHeadings(copy: copy)
            DayTimelineView(
                day: day, layout: layout, now: clock.now, nowText: clock.text,
                copy: copy, renderer: renderer, symbols: symbols, compact: compact, viewportHeight: viewportHeight,
                onBlock: onBlock, onFrame: onFrame)
        } else {
            DayListView(day: day, now: clock.now, copy: copy, onBlock: onBlock)
        }
    }
}

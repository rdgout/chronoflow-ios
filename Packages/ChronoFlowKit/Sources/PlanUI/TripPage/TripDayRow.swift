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
    let viewportHeight: Double
    let onBlock: (String) -> Void
    let onFrame: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.layout == rhs.layout && lhs.clock === rhs.clock
            && lhs.timeline == rhs.timeline && lhs.copy == rhs.copy && lhs.renderer === rhs.renderer
            && lhs.symbols === rhs.symbols && lhs.viewportHeight == rhs.viewportHeight
            && lhs.compact == rhs.compact
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
            clockContent
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DayFrames.self, value: [day.id: geo.frame(in: .named("trip.scroll"))])
            })
    }

    var clockContent: DayClockContent {
        DayClockContent(
            day: day, layout: layout, clock: clock, timeline: timeline, copy: copy,
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

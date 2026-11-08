import DesignSystem
import PlanCore
import SwiftUI

struct TripDayRow: View, Equatable {
    let day: PreparedDay
    let layout: DayLayout?
    let model: TripPlanModel
    let timeline: Bool
    let copy: PageCopy
    let renderer: TimelineRenderer
    let symbols: TimelineSymbols
    let viewportHeight: Double
    let onBlock: (String) -> Void
    let onFrame: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.layout == rhs.layout && lhs.model === rhs.model
            && lhs.timeline == rhs.timeline && lhs.copy == rhs.copy && lhs.renderer === rhs.renderer
            && lhs.symbols === rhs.symbols && lhs.viewportHeight == rhs.viewportHeight
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
            DayClockContent(
                day: day, layout: layout, model: model, timeline: timeline, copy: copy,
                renderer: renderer, symbols: symbols, viewportHeight: viewportHeight, onBlock: onBlock, onFrame: onFrame
            )
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DayFrames.self, value: [day.id: geo.frame(in: .named("trip.scroll"))])
            })
    }
}

private struct DayClockContent: View {
    let day: PreparedDay
    let layout: DayLayout?
    let model: TripPlanModel
    let timeline: Bool
    let copy: PageCopy
    let renderer: TimelineRenderer
    let symbols: TimelineSymbols
    let viewportHeight: Double
    let onBlock: (String) -> Void
    let onFrame: () -> Void

    var body: some View {
        if timeline, let layout {
            LaneHeadings(copy: copy)
            DayTimelineView(
                day: day, layout: layout, now: model.now, nowText: model.nowTexts[day.id] ?? "",
                copy: copy, renderer: renderer, symbols: symbols, viewportHeight: viewportHeight,
                onBlock: onBlock, onFrame: onFrame)
        } else {
            DayListView(day: day, now: model.now, copy: copy, onBlock: onBlock)
        }
    }
}

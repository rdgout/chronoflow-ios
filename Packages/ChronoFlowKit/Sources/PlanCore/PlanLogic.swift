import AppCore
import Foundation

public func isOptionalStep(_ block: BlockView) -> Bool {
    switch block.type {
    case .avoidLight, .seekLight: block.priority == .optional
    case .caffeineOK: true
    case .lightOK, .lightNeutral: block.priority == .info
    default: false
    }
}

public func withoutOptionalSteps(_ plan: PlanView) -> PlanView {
    var value = plan
    value.blocks.removeAll(where: isOptionalStep)
    return value
}

public func tripDisplayStatus(_ card: TripCardView, planStartUtc: String?, planEndUtc: String?, now: Date) -> TripStatus
{
    guard card.progress.status != .completed, let planStartUtc, let planEndUtc else { return card.progress.status }
    if now >= planDate(planEndUtc) { return .completed }
    return planDate(planStartUtc) <= now ? .active : .upcoming
}

public struct NoticeEntry: Sendable, Equatable {
    public var note: NoteView
    public var warning: Bool
}

public func noticeItems(_ plan: PlanView, notices: PlanNoticesView, day: DayView) -> [NoticeEntry] {
    let indexes = notices.days.first { $0.dayId == day.id }?.warningIndexes ?? []
    let warnings = indexes.compactMap {
        plan.warnings.indices.contains($0) ? NoticeEntry(note: plan.warnings[$0], warning: true) : nil
    }
    var entries: [NoticeEntry] = []
    for entry in warnings + day.notes.map({ NoticeEntry(note: $0, warning: $0.role == .warning) }) {
        if let index = entries.firstIndex(where: { $0.note == entry.note }) {
            entries[index].warning = entries[index].warning || entry.warning
        } else {
            entries.append(entry)
        }
    }
    return entries
}

public func dayZoneLabel(_ day: DayView, trip: TripDetailView? = nil) -> String {
    var zones: [String] = []
    for zone in day.zones where !zones.contains(zone.tz) { zones.append(zone.tz) }
    return zones.map { zoneLabel($0, trip: trip) }.joined(separator: " → ")
}

public struct DisplayInterval: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var tz: String
}

public func summaryIntervals(_ day: DayView, blocks: [BlockView], type: BlockType) -> [DisplayInterval] {
    var intervals: [DisplayInterval] = []
    for block in blocks where block.type == type && !isOptionalStep(block) {
        if type == .sleep {
            guard case .sleep(let params) = block.params, [.main, .inFlightMain].contains(params.kind) else { continue }
        }
        let start = max(planDate(day.startUtc), planDate(block.startUtc))
        let end = min(planDate(day.endUtc), planDate(block.endUtc))
        guard start < end else { continue }
        for zone in day.zones {
            let from = max(start, planDate(zone.startUtc))
            let until = min(end, planDate(zone.endUtc))
            if from < until { intervals.append(DisplayInterval(start: from, end: until, tz: zone.tz)) }
        }
    }
    intervals.sort { $0.start < $1.start }
    var merged: [DisplayInterval] = []
    for interval in intervals {
        if let last = merged.last, last.tz == interval.tz, last.end >= interval.start {
            merged[merged.count - 1].end = max(last.end, interval.end)
        } else {
            merged.append(interval)
        }
    }
    return merged
}

public func stepLabelKey(_ type: BlockType) -> String? {
    switch type {
    case .sleep: "Sleep"
    case .nap: "Nap"
    case .rest: "Rest"
    case .seekLight: "Seek bright light"
    case .lightOK: "Normal light is fine"
    case .lightNeutral: "Indoor light"
    case .avoidLight: "Avoid bright light"
    case .caffeineServing: "Caffeine serving"
    case .caffeineRoutine: "Caffeine routine"
    case .caffeineOK: "Caffeine window"
    case .noCaffeine: "Avoid caffeine"
    case .flight: "Flight"
    case .layover: "Layover"
    case .transfer: "Airport transfer"
    case .movementBreak: "Movement break"
    case .zoneChange: "Time-zone change"
    case .note: "Note"
    case .unknown: nil
    }
}

public func dayLabelKey(_ phase: LabelPhase) -> String? {
    switch phase {
    case .preDeparture: "Before departure"
    case .travel: "Travel day"
    case .travelArrivalNight: "Travel · arrival night"
    case .arrivalDay0: "Arrival day"
    case .day: "Day :count"
    case .unknown: nil
    }
}

public func dayStatusLabelKey(_ status: DayStatus) -> String? {
    switch status {
    case .adapting: "Adjusting"
    case .partiallyAdapted: "Partly adapted"
    case .adapted: "Expected adapted"
    case .adaptedSlowerClock: "Protect a slower clock"
    case .unknown: nil
    }
}

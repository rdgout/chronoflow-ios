import AppCore
import Foundation

public struct TodayPlan: Sendable, Equatable {
    public var currentDay: DayView?
    public var currentSteps: [BlockView]
    public var upcomingSteps: [BlockView]
    public var marks: [CheckMark]
    public var dayProgress: DayCheckProgressView?
    public var allCategoriesHidden: Bool
    public var importantHidden: Bool
    public var nextStep: BlockView?
    public var minutesUntilNext: Int
    public var beforePlan: Bool
    public var afterPlan: Bool
}

public func todayView(_ detail: TripDetail, marks: [CheckMark], now: Date, hidden: [BlockType] = []) -> TodayPlan {
    let plan = withoutOptionalSteps(detail.plan)
    let state = buildCheckState(plan, marks: marks)
    let marked = Set(marks.map { checkIdentity($0.key) })
    let excluded = Set(hidden + [.lightOK, .lightNeutral])
    let blocks = plan.renderableBlocks.filter { !excluded.contains($0.type) }
    let day = plan.days.first { planDate($0.startUtc) <= now && now < planDate($0.endUtc) }
    let next = plan.blocks.first { block in
        block.actionable && block.checkKey.map { !marked.contains(checkIdentity($0)) } == true
            && planDate(block.endUtc) > now
    }
    let categories: [BlockType] = [
        .sleep, .nap, .rest, .seekLight, .lightOK, .lightNeutral, .avoidLight,
        .caffeineServing, .caffeineRoutine, .caffeineOK, .noCaffeine, .flight, .layover, .transfer, .movementBreak,
        .zoneChange, .note,
    ]
    return TodayPlan(
        currentDay: day,
        currentSteps: blocks.filter { planDate($0.startUtc) <= now && now < planDate($0.endUtc) },
        upcomingSteps: Array(blocks.filter { planDate($0.startUtc) > now }.prefix(4)),
        marks: state.marks, dayProgress: day.flatMap { day in state.days.first { $0.dayId == day.id } },
        allCategoriesHidden: categories.allSatisfy(hidden.contains),
        importantHidden: detail.plan.blocks.contains { $0.priority == .core && hidden.contains($0.type) },
        nextStep: next,
        minutesUntilNext: next.map { max(0, Int(ceil(planDate($0.startUtc).timeIntervalSince(now) / 60))) } ?? 0,
        beforePlan: now < planDate(plan.days.first?.startUtc ?? detail.trip.departureUtc),
        afterPlan: now >= planDate(plan.days.last?.endUtc ?? detail.trip.endUtc))
}

public func calendarDaysUntil(_ at: String, now: Date, zone: String) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
    return max(
        0,
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: planDate(at)))
            .day ?? 0)
}

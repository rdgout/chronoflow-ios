import AppCore
import Foundation

public func checkIdentity(_ key: CheckKeyView) -> String {
    "\(key.type.rawValue)|\(key.localDate)|\(key.ordinal)"
}

public func buildCheckState(_ plan: PlanView, marks: [CheckMark]) -> CheckState {
    let actionable = plan.blocks.filter(\.actionable)
    let current = Dictionary(
        actionable.compactMap { block in
            block.checkKey.map { (checkIdentity($0), block) }
        }, uniquingKeysWith: { _, last in last })
    let matching = marks.filter { current[checkIdentity($0.key)] != nil }
    return CheckState(
        planInputHash: plan.meta.inputHash, marks: matching,
        days: plan.days.map { day in
            func startsOnDay(_ block: BlockView) -> Bool {
                planDate(day.startUtc) <= planDate(block.startUtc) && planDate(block.startUtc) < planDate(day.endUtc)
            }
            let dayMarks = matching.filter { mark in current[checkIdentity(mark.key)].map(startsOnDay) == true }
            return DayCheckProgressView(
                dayId: day.id, done: dayMarks.filter { $0.status == .done }.count,
                skipped: dayMarks.filter { $0.status == .skipped }.count,
                total: actionable.filter(startsOnDay).count)
        })
}

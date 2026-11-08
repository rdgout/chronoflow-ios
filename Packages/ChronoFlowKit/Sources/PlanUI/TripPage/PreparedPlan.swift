import AppCore
import Foundation
import PlanCore

nonisolated public struct PreparedBlock: Sendable, Equatable, Identifiable {
    public var id: String { block.id }
    public var block: BlockView
    public var title: String
    public var interval: String
    public var priority: String
    public var reason: String?
    public var instructions: String
    public var accessibilityLabel: String
    public var status: CheckStatus?
    public var continuesBefore: Bool
    public var continuesAfter: Bool
    public var zoneInstruction: String?
    public var zoneComparison: String?
}

nonisolated public struct PreparedNotice: Sendable, Equatable {
    public var text: String
    public var warning: Bool
}

nonisolated public struct PreparedDay: Sendable, Equatable, Identifiable {
    public var id: String { day.id }
    public var day: DayView
    public var title: String
    public var date: String
    public var weekday: String
    public var dayMonth: String
    public var zone: String
    public var status: String?
    public var summary: String
    public var headline: String?
    public var notices: [PreparedNotice]
    public var warningCount: Int
    public var progress: String
    public var blocks: [PreparedBlock]
    public var dividerLabels: [String]
    public var ticks: [String]

    public func shownNotices(expanded: Bool, notesOpen: Bool) -> [PreparedNotice] {
        expanded && (warningCount > 0 || notesOpen) ? notices : []
    }
}

nonisolated public struct PreparedPlan: Sendable, Equatable {
    public var revision: String
    public var days: [PreparedDay]
    public var title: String
    public var subtitle: String
    public var spokenDates: String
    public var shift: String?
    public var summary: String
    public var endText: String
    public var assumedEnd: String?
    public var returnDayID: String?
}

nonisolated public func preparePlan(
    _ detail: TripDetail, layouts: [String: DayLayout], formatter: CopyLineFormatter,
    language: Language, timeFormat: TimeFormat = .value24, marks: [CheckMark] = [], pendingChecks: [CheckOffChange] = []
) -> PreparedPlan {
    let copy = PageCopy(language: language)
    let options = CopyFormat(language: language, timeFormat: timeFormat, trip: detail.trip)
    let plan = detail.plan
    let visible = withoutOptionalSteps(plan)
    let dayBlocks = timelineBlocksByDay(visible)
    var index = Dictionary(
        (detail.checkState.marks + marks).map { (checkIdentity($0.key), $0.status) },
        uniquingKeysWith: { _, new in new })
    for change in pendingChecks {
        let key = CheckKeyView(type: change.type, localDate: change.localDate, ordinal: change.ordinal)
        index[checkIdentity(key)] = change.status
    }
    let days = plan.days.compactMap { day -> PreparedDay? in
        guard let layout = layouts[day.id] else { return nil }
        let placed = timelineLanes.flatMap { layout.placed[$0] ?? [] }
        let blocks = (placed.map(\.block) + layout.markers.map(\.block) + layout.changes.map(\.block))
            .sorted { $0.startUtc == $1.startUtc ? $0.id < $1.id : planDate($0.startUtc) < planDate($1.startUtc) }
            .map { block -> PreparedBlock in
                let p = placed.first { $0.block.id == block.id }
                let title = formatter.format(block.text, options: options)
                let interval =
                    block.type == .zoneChange
                    ? formatter.formatInstant(block.startUtc, options: options, zone: block.displayTz)
                    : formatter.blockInterval(block, options: options)
                let priority = copy(priorityKey(block.priority))
                let status = block.actionable ? block.checkKey.flatMap { index[checkIdentity($0)] } : nil
                let before = p?.continuesBefore ?? false
                let after = p?.continuesAfter ?? false
                let label = [
                    title, priority, interval, status.map { copy($0 == .done ? "Marked done" : "Skipped") },
                    before ? copy("Continues from the previous plan day") : nil,
                    after ? copy("Continues into the next plan day") : nil,
                ].compactMap { $0 }.joined(separator: ", ")
                var instruction: String?
                var comparison: String?
                if case .zoneChange(let params) = block.params {
                    let from = block.secondaryTz ?? detail.trip.from.zone
                    let to = block.displayTz
                    let destination = zoneLabel(to, trip: detail.trip)
                    instruction = copy(
                        "From here on all times are %@ time. Set your watch to %@.", destination,
                        formatter.formatInstant(block.startUtc, options: options, zone: to))
                    comparison =
                        "\(zoneLabel(from, trip: detail.trip)) \(formatter.formatInstant(block.startUtc, options: options, zone: from)) → \(destination) \(interval) · \(formatter.formatOffset(Double(params.offsetMin), language: language))"
                }
                return PreparedBlock(
                    block: block, title: title, interval: interval, priority: priority,
                    reason: p?.presentation.reasons.first.map { formatter.format($0, options: options) },
                    instructions: ([block.text] + (block.secondaryText.map { [$0] } ?? [])).map {
                        formatter.format($0, options: options)
                    }.joined(separator: " "),
                    accessibilityLabel: label, status: status, continuesBefore: before, continuesAfter: after,
                    zoneInstruction: instruction, zoneComparison: comparison)
            }
        let notices = noticeItems(plan, notices: detail.notices, day: day)
        let summary = [BlockType.sleep, .seekLight].map { type in
            let intervals = summaryIntervals(day, blocks: dayBlocks[day.id] ?? [], type: type)
            if intervals.isEmpty, type == .seekLight, let line = day.noLightText {
                return formatter.format(line, options: options)
            }
            return copy(type == .sleep ? "Sleep" : "Light") + " "
                + intervals.map {
                    formatter.formatInstant($0.start.ISO8601Format(), options: options, zone: $0.tz) + "–"
                        + formatter.formatInstant($0.end.ISO8601Format(), options: options, zone: $0.tz)
                }.joined(separator: ", ")
        }.joined(separator: " · ")
        let actionable = blocks.filter { $0.block.actionable && $0.block.checkKey != nil }
        return PreparedDay(
            day: day,
            title: formatter.catalog.text(
                dayLabelKey(day.labelPhase) ?? "", language: language,
                arguments: ["count": String(day.postArrivalIndex ?? 0)], count: Double(day.postArrivalIndex ?? 0)),
            date: formatter.dayDateLabel(day, language: language),
            weekday: formatter.formatWeekday(day.labelDate, language: language),
            dayMonth: formatter.formatDayMonth(day.labelDate, language: language),
            zone: dayZoneLabel(day, trip: detail.trip),
            status: day.status.flatMap(dayStatusLabelKey).map { formatter.catalog.text($0, language: language) },
            summary: summary, headline: day.headline.map { formatter.format($0, options: options) },
            notices: notices.map {
                PreparedNotice(
                    text: $0.note.lines.map { formatter.format($0, options: options) }.joined(separator: " "),
                    warning: $0.warning)
            },
            warningCount: notices.filter(\.warning).count,
            progress: copy(
                "%@ of %@ steps done", String(actionable.filter { $0.status == .done }.count), String(actionable.count)),
            blocks: blocks,
            dividerLabels: layout.dividers.map { copy("%@ time from here", zoneLabel($0.after.tz, trip: detail.trip)) },
            ticks: layout.ticks.map { formatter.formatInstant($0.tick.atUtc, options: options, zone: $0.tick.tz) })
    }
    let hasReturn = detail.trip.legs.contains(where: \.returnLeg)
    let endNote = plan.days.flatMap(\.notes).last { $0.role == .end }
    let endSummary = hasReturn ? nil : plan.summary
    let endLines = endNote?.lines ?? endSummary?.endCopy ?? []
    var seen: [CopyLine] = []
    let end = (endSummary?.expectedAdaptedText.map { [$0] } ?? []) + endLines.filter { $0.key != "How this plan ends" }
    let stateKey: String? =
        switch endNote?.endState ?? endSummary?.endState {
        case .adapted: endSummary?.expectedAdaptedText == nil ? "Expected adapted" : nil
        case .likelyAdapted: "Likely adapted"
        case .stillAdapting: "Still adjusting"
        case .partialTarget: "Partial shift"
        case .smallShift: "Keep your usual rhythm"
        case .returnPlanStarts: "Return plan starts"
        case .homeTime: "Stay closer to home time"
        case .hold: "Holding this shift"
        default: nil
        }
    let ending = end.filter { line in
        if seen.contains(line) { return false }
        seen.append(line)
        return true
    }.map { formatter.format($0, options: options) }.joined(separator: " ")
    let endText = [stateKey.map { copy($0) }, ending.isEmpty ? nil : ending].compactMap { $0 }.joined(separator: " · ")
    let zone = plan.days.last?.zones.last?.tz ?? detail.trip.to.zone
    let assumedEnd = (hasReturn ? nil : plan.meta.assumedReturn).map {
        [
            copy("Assumed trip end"), formatter.formatDate($0.leaveUtc, language: language, zone: zone),
            formatter.formatInstant($0.leaveUtc, options: options, zone: zone), zoneLabel(zone, trip: detail.trip),
            $0.basis == .checkOut
                ? copy("Based on your check-out date") : copy("Based on %@ nights", String($0.nights)),
        ].joined(separator: " · ")
    }
    let summary = [plan.summary?.rationale, plan.summary?.expectedAdaptedText].compactMap { $0 }.map {
        formatter.format($0, options: options)
    }.joined(separator: " ")
    return PreparedPlan(
        revision: detail.plan.meta.inputHash + "|" + detail.detailVersion, days: days,
        title: "\(detail.trip.from.city ?? detail.trip.from.iata) → \(detail.trip.to.city ?? detail.trip.to.iata)",
        subtitle: tripMetaText(
            start: detail.trip.departLocal, end: plan.days.last?.labelDate,
            flights: detail.trip.legs.filter { !$0.returnLeg }.compactMap(\.flightNumber), language: language),
        spokenDates: tripDatesText(
            start: detail.trip.departLocal, end: plan.days.last?.labelDate,
            language: language, long: true),
        shift: plan.summary.map { clockShiftText($0.adaptation, formatter: formatter, options: options) },
        summary: summary,
        endText: endText.isEmpty ? copy("There are no more steps in this plan.") : endText, assumedEnd: assumedEnd,
        returnDayID: returnDayID(detail))

}

nonisolated public func priorityKey(_ priority: Priority) -> String {
    switch priority {
    case .core: "Important"
    case .recommended: "Recommended"
    case .optional: "Optional"
    default: "Information"
    }
}

nonisolated private func returnDayID(_ detail: TripDetail) -> String? {
    let positions = Set(detail.trip.legs.filter(\.returnLeg).map(\.position))
    guard
        let flight = detail.plan.blocks.first(where: {
            if case .flight(let params) = $0.params { return positions.contains(params.legIndex) }
            return false
        })
    else { return nil }
    return detail.plan.days.first {
        planDate($0.startUtc) <= planDate(flight.startUtc) && planDate(flight.startUtc) < planDate($0.endUtc)
    }?.id
}

nonisolated func clockShiftText(_ adaptation: AdaptationView, formatter: CopyLineFormatter, options: CopyFormat)
    -> String
{
    let copy = PageCopy(language: options.language)
    guard adaptation.direction != .none else { return copy("No clock shift planned") }
    let duration =
        adaptation.shiftMin % 60 == 0
        ? copy("%@ hours", String(adaptation.shiftMin / 60))
        : formatter.formatMinutes(Double(adaptation.shiftMin), language: options.language, duration: true)
    return copy(adaptation.direction == .earlier ? "We advance your clock %@" : "We delay your clock %@", duration)
}

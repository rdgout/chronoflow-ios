import AppCore
import Foundation

public struct BlockPresentation: Sendable, Equatable {
    public var reasons: [CopyLine]
    public var warningIndexes: [Int]
}

public struct PlacedBlock: Sendable, Equatable {
    public var block: BlockView
    public var top: Double
    public var height: Double
    public var exactTop: Double
    public var tiny: Bool
    public var col: Int
    public var cols: Int
    public var continuesBefore: Bool
    public var continuesAfter: Bool
    public var presentation: BlockPresentation
}

public struct PlacedMarker: Sendable, Equatable {
    public var block: BlockView
    public var exactTop: Double
    public var top: Double
    public var presentation: BlockPresentation
}

public struct ZoneChangePosition: Sendable, Equatable {
    public var block: BlockView
    public var top: Double
}

public struct ZoneDivider: Sendable, Equatable {
    public var before: DayZoneView
    public var after: DayZoneView
    public var top: Double
}

public struct TickPosition: Sendable, Equatable {
    public var tick: TickView
    public var top: Double
    public var visible: Bool
}

public struct TimelineIndex: Sendable, Equatable {
    public var ticks: [String: [TickView]]
    public var blockReasons: [String: [CopyLine]]
    public var transferWarnings: [String: [Int]]
}

public struct DayLayout: Sendable, Equatable {
    public var day: DayView
    public var height: Double
    public var minWidth: Double
    public var placed: [Lane: [PlacedBlock]]
    public var markers: [PlacedMarker]
    public var changes: [ZoneChangePosition]
    public var dividers: [ZoneDivider]
    public var ticks: [TickPosition]
}

public var timelineLanes: [Lane] { [.sleep, .light, .caffeine, .travel] }

public func indexTimeline(_ timeline: TimelinePresentationView) -> TimelineIndex {
    TimelineIndex(
        ticks: Dictionary(timeline.days.map { ($0.dayId, $0.ticks) }, uniquingKeysWith: { _, last in last }),
        blockReasons: Dictionary(
            timeline.blockReasons.map { ($0.blockId, $0.lines) }, uniquingKeysWith: { _, last in last }),
        transferWarnings: Dictionary(
            timeline.transferWarnings.map { ($0.blockId, $0.warningIndexes) }, uniquingKeysWith: { _, last in last }))
}

private func offsetFrom(_ start: Date, _ at: Date) -> Double {
    at.timeIntervalSince(start) / 60 * PlanMetrics.pointsPerMinute
}

public func nowLineOffset(_ day: DayView, now: Date) -> Double? {
    let start = planDate(day.startUtc)
    return start <= now && now < planDate(day.endUtc) ? offsetFrom(start, now) : nil
}

public func zoneChangePositions(_ day: DayView, blocks: [BlockView]) -> [ZoneChangePosition] {
    let start = planDate(day.startUtc)
    let end = planDate(day.endUtc)
    return blocks.filter { $0.type == .zoneChange && start <= planDate($0.startUtc) && planDate($0.startUtc) < end }
        .sorted { planDate($0.startUtc) < planDate($1.startUtc) }
        .map { ZoneChangePosition(block: $0, top: offsetFrom(start, planDate($0.startUtc))) }
}

public func tickPositions(_ day: DayView, ticks: [TickView]) -> [TickPosition] {
    let start = planDate(day.startUtc)
    let end = planDate(day.endUtc)
    let inside = ticks.filter { start <= planDate($0.atUtc) && planDate($0.atUtc) < end }
    let positions = inside.map { offsetFrom(start, planDate($0.atUtc)) }
    let mandatory = inside.indices.map {
        $0 == 0 || inside[$0].tz != inside[$0 - 1].tz || inside[$0].offsetMin != inside[$0 - 1].offsetMin
    }
    var visible: [Int] = []
    for index in inside.indices {
        if mandatory[index] {
            while let last = visible.last,
                positions[index] - positions[last] < PlanMetrics.minTickSpacing && !mandatory[last]
            { visible.removeLast() }
            visible.append(index)
        } else if let last = visible.last, positions[index] - positions[last] >= PlanMetrics.minTickSpacing {
            visible.append(index)
        }
    }
    let shown = Set(visible)
    return inside.indices.map { TickPosition(tick: inside[$0], top: positions[$0], visible: shown.contains($0)) }
}

public func packLane(_ items: inout [PlacedBlock]) {
    items.sort { $0.top == $1.top ? $0.exactTop < $1.exactTop : $0.top < $1.top }
    var group: [Int] = []
    var columnEnds: [Double] = []
    var groupEnd = -Double.infinity
    func flush() {
        for index in group { items[index].cols = columnEnds.count }
        group.removeAll(keepingCapacity: true)
        columnEnds.removeAll(keepingCapacity: true)
    }
    for index in items.indices {
        if items[index].top >= groupEnd { flush() }
        let col = columnEnds.firstIndex { $0 <= items[index].top } ?? columnEnds.count
        items[index].col = col
        let end = items[index].top + items[index].height
        if col == columnEnds.count { columnEnds.append(end) } else { columnEnds[col] = end }
        group.append(index)
        groupEnd = max(groupEnd, end)
    }
    flush()
}

public func layoutDay(_ day: DayView, blocks: [BlockView], presentation: TimelineIndex, hidden: Set<BlockType> = [])
    -> DayLayout
{
    let start = planDate(day.startUtc)
    let end = planDate(day.endUtc)
    let height = offsetFrom(start, end)
    var placed = Dictionary(uniqueKeysWithValues: timelineLanes.map { ($0, [PlacedBlock]()) })
    var markers: [PlacedMarker] = []
    for block in blocks {
        guard block.isSupported, !isOptionalStep(block), !hidden.contains(block.type), block.type != .zoneChange else {
            continue
        }
        let a = planDate(block.startUtc)
        let b = planDate(block.endUtc)
        if a >= end || (b <= start && !(a == b && a >= start)) { continue }
        let exactTop = offsetFrom(start, max(start, a))
        let details = BlockPresentation(
            reasons: presentation.blockReasons[block.id] ?? [],
            warningIndexes: presentation.transferWarnings[block.id] ?? [])
        if block.lane == .info {
            markers.append(
                PlacedMarker(
                    block: block, exactTop: exactTop, top: exactTop + PlanMetrics.gutterMarkerSize / 2,
                    presentation: details))
            continue
        }
        let tileHeight = min(height, max(PlanMetrics.minTileHeight, offsetFrom(max(start, a), min(end, b))))
        placed[block.lane, default: []].append(
            PlacedBlock(
                block: block, top: min(exactTop, height - tileHeight), height: tileHeight, exactTop: exactTop,
                tiny: tileHeight <= PlanMetrics.tinyTileHeight, col: 0, cols: 1, continuesBefore: a < start,
                continuesAfter: b > end, presentation: details))
    }
    for lane in timelineLanes { packLane(&placed[lane]!) }
    markers.sort { $0.exactTop < $1.exactTop }
    for index in markers.indices.dropFirst() {
        markers[index].top = max(markers[index].top, markers[index - 1].top + PlanMetrics.gutterMarkerSize)
    }
    let columns = timelineLanes.map { lane in max(1, placed[lane]!.map(\.cols).max() ?? 1) }
    let dividers = day.zones.indices.dropFirst().compactMap { index -> ZoneDivider? in
        let at = planDate(day.zones[index].startUtc)
        return start <= at && at < end
            ? ZoneDivider(before: day.zones[index - 1], after: day.zones[index], top: offsetFrom(start, at)) : nil
    }
    return DayLayout(
        day: day, height: height,
        minWidth: PlanMetrics.gutterWidth + Double(timelineLanes.count) * PlanMetrics.laneGap
            + columns.reduce(0) { $0 + max(PlanMetrics.minLaneWidth, Double($1) * PlanMetrics.minColumnWidth) },
        placed: placed, markers: markers,
        changes: hidden.contains(.zoneChange) ? [] : zoneChangePositions(day, blocks: blocks.filter(\.isSupported)),
        dividers: dividers, ticks: tickPositions(day, ticks: presentation.ticks[day.id] ?? []))
}

public func layoutPlan(_ plan: PlanView, timeline: TimelinePresentationView, hidden: [BlockType] = []) -> [String:
    DayLayout]
{
    let presentation = indexTimeline(timeline)
    let excluded = Set(hidden)
    return Dictionary(
        uniqueKeysWithValues: plan.days.map {
            ($0.id, layoutDay($0, blocks: plan.blocks, presentation: presentation, hidden: excluded))
        })
}

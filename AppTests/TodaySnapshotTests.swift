import AppCore
import PlanCore
import PlanUI
import SwiftUI
import XCTest

nonisolated enum TodaySnapshotState: String, CaseIterable {
    case active, empty, future, loading, completed, done, skipped, hidden, allHidden, nothingNow
}

@MainActor func todayFixture(_ state: TodaySnapshotState, formatter: CopyLineFormatter) throws -> TodayScreen {
    let account = try PlanScreenFixture.account()
    var detail = try PlanScreenFixture.detail()
    let now = PlanScreenFixture.now
    var trips = account.trips.map { item in
        TripListValue(
            card: item.card, planStartUtc: item.planStartUtc, planEndUtc: item.planEndUtc,
            status: item.card.progress.status, planStartZone: item.planStartZone,
            planEndDate: item.planEndDate, preparationDays: item.preparationDays)
    }
    var hidden: [BlockType] = []
    switch state {
    case .empty: trips = []
    case .completed: trips = trips.filter { $0.status == .completed }
    case .future: trips = trips.filter { $0.status == .upcoming }
    case .done, .skipped:
        if let block = detail.plan.blocks.first(where: {
            $0.actionable && $0.checkKey != nil && planDate($0.endUtc) > now
        }), let key = block.checkKey {
            detail.checkState.marks = [
                CheckMark(key: key, status: state == .done ? .done : .skipped, markedAt: now.ISO8601Format())
            ]
        }
    case .hidden: hidden = detail.plan.blocks.filter { $0.priority == .core }.map(\.type)
    case .allHidden:
        hidden = [
            .sleep, .nap, .rest, .seekLight, .lightOK, .lightNeutral, .avoidLight, .caffeineServing, .caffeineRoutine,
            .caffeineOK, .noCaffeine, .flight, .layover, .transfer, .movementBreak, .zoneChange, .note,
        ]
    case .nothingNow: detail.plan.blocks.removeAll { planDate($0.startUtc) <= now }
    default: break
    }
    return TodayScreen(
        trips: trips, detail: detail, now: now, loading: state == .loading, formatter: formatter,
        hidden: hidden, openTrip: { _ in }, openStep: { _ in }, settings: {}, pastTrips: {})
}

nonisolated final class TodaySnapshotTests: XCTestCase {
    @MainActor func testEveryTodayStateInLeanProfiles() async throws {
        let formatter = try await PlanScreenFixture.formatter()
        try await planSnapshots("Today", states: TodaySnapshotState.allCases) { state in
            let screen = try todayFixture(state, formatter: formatter)
            return NavigationStack { screen }
        }
    }
}

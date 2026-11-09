#if DEBUG
    import AppCore
    import PlanCore
    import PlanUI
    import SwiftUI
    import XCTest

    nonisolated enum TripsSnapshotState: String, CaseIterable { case list, empty, loading }

    @MainActor func tripsFixture(
        _ state: TripsSnapshotState, formatter: CopyLineFormatter, refresh: @escaping () async -> Void = {}
    ) throws -> TripsScreen {
        let account = try PlanScreenFixture.account()
        let trips = account.trips.map { item in
            TripListValue(
                card: item.card, planStartUtc: item.planStartUtc, planEndUtc: item.planEndUtc,
                status: item.card.progress.status, planStartZone: item.planStartZone,
                planEndDate: item.planEndDate, preparationDays: item.preparationDays)
        }
        return TripsScreen(
            trips: state == .empty ? [] : trips, details: account.details, now: PlanScreenFixture.now,
            loading: state == .loading, formatter: formatter, open: { _ in }, refresh: refresh)
    }

    nonisolated final class TripsSnapshotTests: XCTestCase {
        @MainActor func testEveryTripsStateInLeanProfiles() async throws {
            let formatter = try await PlanScreenFixture.formatter()
            try await planSnapshots("Trips", states: TripsSnapshotState.allCases) { state in
                let screen = try tripsFixture(state, formatter: formatter)
                return NavigationStack { screen }
            }
        }
    }
#endif

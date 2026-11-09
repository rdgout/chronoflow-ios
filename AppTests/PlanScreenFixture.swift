import AppCore
import DataAccess
import Foundation
import PlanCore

@MainActor enum PlanScreenFixture {
    static var now: Date { planDate("2026-11-08T10:00:00Z") }
    static func account() throws -> MockServerAccount {
        let state = try MockAppSeed.make(now: now, walkthroughSeen: true)
        return state.accounts.values.sorted { $0.snapshot.id < $1.snapshot.id }[0]
    }
    static func detail() throws -> TripDetail {
        let account = try account()
        let trip =
            try account.trips.first { $0.card.progress.status == .active }
            .map { $0.card.id } ?? account.trips[0].card.id
        return account.details[trip]!
    }
    static func formatter() async throws -> CopyLineFormatter {
        try await CopyLineFormatter(catalog: CopyCatalog.load())
    }
}

#if DEBUG
    import AppCore
    import DataAccess
    import Foundation
    import LocalStore
    import PlanUI
    import SwiftUI
    import Sync

    struct TripPageDiagnosticRoot: View {
        let requestedTrip: String
        @State private var model: TripPageModel?
        @State private var failure: String?
        @State private var database: AccountDatabase?
        var body: some View {
            NavigationStack {
                if let model {
                    TripPageView(model: model)
                } else if let failure {
                    Text(verbatim: failure).accessibilityIdentifier("trip.diagnostic.failure")
                }
            }.task {
                do {
                    let seed = try await Task.detached { try MockAppSeed.make(now: Date(), walkthroughSeen: true) }
                        .value
                    let account = seed.accounts[MockScenarioValues.demoID]!
                    let id: String
                    if requestedTrip.hasPrefix("S"), let index = Int(requestedTrip.dropFirst()),
                        account.trips.indices.contains(index - 1)
                    {
                        id = account.trips[index - 1].card.id
                    } else {
                        id = requestedTrip
                    }
                    guard let item = account.trips.first(where: { $0.card.id == id }), let detail = account.details[id]
                    else { throw DataFailure.server(status: 404) }
                    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                        "Timeline-\(UUID().uuidString)")
                    let db = AccountDatabase(applicationSupport: root, namespace: .mock)
                    try await db.open(accountID: account.snapshot.id)
                    let repo = TripRepository(database: db)
                    let record = try await Task.detached {
                        try TripRecord(
                            id: id, card: .encoding(item.card), currentInputHash: item.planInputHash,
                            keepOffline: item.keepOffline, departureUtc: item.card.departureUtc)
                    }.value
                    try await repo.upsert(record)
                    try await repo.store(
                        plan: PlanVersionRecord(
                            tripId: id, inputHash: detail.plan.meta.inputHash, detail: .encoding(detail),
                            receivedAt: Date().ISO8601Format(), detailVersion: detail.detailVersion), checks: [])
                    database = db
                    model = TripPageModel(tripID: id, repository: repo, retention: PlanRetention())
                } catch { failure = String(describing: error) }
            }
        }
        static var requestedTrip: String? {
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: "-cf.trip-page"), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
    }
#endif

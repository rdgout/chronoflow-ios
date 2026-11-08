import AppCore
import Foundation
import LocalStore
import PlanCore
import Sync
import Testing

@testable import PlanUI

private actor DetailRequests {
    var count = 0
    func fetch(_ id: String) throws {
        count += 1
        if count == 1 { throw DataFailure.offline }
    }
}

struct TripPageFetchTests {
    @Test @MainActor func offlineFailureReconnectAndLivePreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = AccountDatabase(applicationSupport: root)
        try await db.open(accountID: "00000000-0000-4000-8000-000000000016")
        let repo = TripRepository(database: db)
        let requests = DetailRequests()
        let model = TripPageModel(
            tripID: "remote", repository: repo, retention: PlanRetention(), awaitingSync: true, path: nil,
            fetchDetail: { try await requests.fetch($0) })
        model.start()
        defer { model.stop() }
        try await ModelTests().eventually { model.fetch == .offline }
        #expect(model.online)
        #expect(model.state == .loading)
        model.online = false
        model.online = true
        try await ModelTests().eventually { model.fetch == .loaded }
        #expect(await requests.count == 2)
        model.online = true
        #expect(await requests.count == 2)
        let settings = SettingsRepository(database: db)
        try await settings.upsert(
            SettingsRecord(
                section: "preferences",
                value: try .encoding(
                    JSONObject([
                        "timeFormat": .string("12"), "hiddenCategories": .array([.string("sleep"), .string("nap")]),
                    ]))))
        try await ModelTests().eventually {
            model.plan.timeFormat == .value12 && model.plan.hiddenCategories == [.sleep, .nap]
        }
        try await settings.upsert(
            SettingsRecord(
                section: "preferences",
                value: try .encoding(
                    JSONObject([
                        "timeFormat": .string("24"), "hiddenCategories": .array([]),
                    ]))))
        try await ModelTests().eventually { model.plan.timeFormat == .value24 && model.plan.hiddenCategories.isEmpty }
        model.stop()
        try await db.close()
    }

    @Test func awaitingSyncOnlySuppressesMissing() {
        for fetch in [TripPageFetch.offline, .failed, .notFound, .loading] {
            let expected: TripPageState =
                switch fetch {
                case .offline: .remoteOffline
                case .failed: .server
                case .notFound: .notFound
                default: .remoteLoading
                }
            #expect(
                TripPageState.resolve(
                    keepOffline: false, stored: false, online: true, fetch: fetch,
                    missingAfterSync: true, awaitingSync: true) == expected)
        }
    }
}

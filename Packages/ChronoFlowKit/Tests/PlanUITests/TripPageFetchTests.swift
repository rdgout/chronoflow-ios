import AppCore
import DataAccess
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
    @Test @MainActor func injectedOfflinePathAndClockStayFrozenAfterStarting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: "00000000-0000-4000-8000-000000000018")
        let repository = TripRepository(database: database)
        let fixture = try MockTimelineFixtures.fixture(named: "S3")
        let adaptation = try #require(fixture.detail.plan.summary?.adaptation)
        try await repository.upsert(
            TripRecord(
                id: fixture.card.id, card: .encoding(fixture.card), adaptation: .encoding(adaptation),
                keepOffline: false, departureUtc: fixture.card.departureUtc))
        let now = planDate(fixture.detail.plan.days[1].startUtc)
        let requests = DetailRequests()
        let model = TripPageModel(
            tripID: fixture.card.id, repository: repository, retention: PlanRetention(), path: nil,
            clock: TestPlanClock(now), now: now, fetchDetail: { try await requests.fetch($0) })
        model.online = false
        model.start()
        defer { model.stop() }
        try await ModelTests().eventually { model.plan.card != nil && model.plan.adaptation != nil }
        for _ in 0..<10 {
            await Task.yield()
            model.start()
            #expect(!model.online)
            #expect(model.state == .remoteOffline)
            #expect(model.plan.now == now)
            #expect(await requests.count == 0)
        }
        model.online = true
        try await ModelTests().eventually { model.fetch == .offline }
        #expect(model.state == .remoteOffline)
        #expect(await requests.count == 1)
        model.retry()
        try await ModelTests().eventually { model.fetch == .loaded }
        #expect(model.state == .remoteLoading)
        #expect(await requests.count == 2)
        model.stop()
        try await database.close()
    }

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
        var card = try MockTimelineFixtures.fixture(named: "S3").card
        card.id = "remote"
        try await repo.upsert(TripRecord(id: "remote", card: try .encoding(card), departureUtc: card.departureUtc))
        try await ModelTests().eventually { model.plan.tripRecord != nil && !model.awaitingSync }
        #expect(model.state == .remoteOffline)
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

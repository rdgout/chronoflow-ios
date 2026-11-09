import AppCore
import GRDB
import LocalStore
import Sync
import Testing

@Suite struct FullPullTests {
    @Test func orderMarkerAndDetailVersion() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let pull = FullPull(database: store.database, source: source, now: { syncDate })
        _ = try await pull.run(epoch: store.epoch)
        #expect(await source.calls == ["identity", "account", "trips", "detail"])
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt == syncDate.ISO8601Format())
        _ = try await pull.run(epoch: store.epoch)
        #expect(await source.calls.filter { $0 == "detail" }.count == 1)
        await source.configure(trips: [card(version: "v2")], detail: detail(version: "v2"))
        _ = try await pull.run(epoch: store.epoch)
        #expect(await source.calls.filter { $0 == "detail" }.count == 2)
        #expect(
            try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash")?.detailVersion
                == "v2")
        try await store.close()
    }
    @Test func unverifiedStopsBeforeProtectedPulls() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        await source.configure(identity: identity(verified: false))
        let result = try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.verificationRequired)
        #expect(await source.calls == ["identity"])
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt == nil)
        #expect(try await AccountRepository(database: store.database).account()?.hasVerifiedEmail == false)
        try await store.close()
    }
    @Test func accountAndCardsRollbackTogether() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        var invalid = card()
        invalid.card["departureUtc"] = nil
        await source.configure(trips: [invalid])
        await #expect(throws: (any Error).self) {
            try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        }
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt == nil)
        #expect(try await SettingsRepository(database: store.database).settings().map(\.section) == ["policies"])
        #expect(try await TripRepository(database: store.database).trips().first?.deletedAt == nil)
        try await store.close()
    }
    @Test func markerSurvivesPartialAndOfflineFailure() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        await source.configure(failMethod: "detail", methodFailure: .server(status: 500))
        let pull = FullPull(database: store.database, source: source, now: { syncDate })
        #expect(try await pull.run(epoch: store.epoch).retryAfter == 1)
        let marker = try await AccountRepository(database: store.database).account()?.syncedAt
        #expect(marker != nil)
        await source.configure(failMethod: "trips")
        await #expect(throws: DataFailure.offline) { try await pull.run(epoch: store.epoch) }
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt == marker)
        try await store.close()
    }
    @Test func emptyTombstonesAndNoLocalResurrection() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let pull = FullPull(database: store.database, source: source)
        _ = try await pull.run(epoch: store.epoch)
        await source.configure(trips: [])
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).trips().first?.deletedAt != nil)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") == nil)
        try await store.database.write { db in try db.execute(sql: "UPDATE trips SET deleted_locally=1") }
        await source.configure(trips: [card()])
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).trips().first?.deletedAt != nil)
        #expect(await source.calls.filter { $0 == "detail" }.count == 1)
        try await store.close()
    }
    @Test func detail404TombstonesWithoutRetry() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        await source.configure(failMethod: "detail", methodFailure: .server(status: 404))
        let result = try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.retryAfter == nil)
        #expect(try await TripRepository(database: store.database).trips().first?.deletedAt != nil)
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt != nil)
        try await store.close()
    }
}

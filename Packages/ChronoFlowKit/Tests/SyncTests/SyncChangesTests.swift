import AppCore
import DataAccess
import Foundation
import LocalStore
import Testing

@testable import Sync

@Suite struct SyncChangesTests {
    private func source(remoteTripUpdate: @escaping @Sendable () async -> Bool = { false }) async throws
        -> MockDataSource
    {
        let source = MockDataSource(
            seed: MockServerState(
                accounts: [
                    MockServerAccount(
                        snapshot: snapshot(), password: "fixture-password", trips: [card()],
                        details: [syncTrip: detail()])
                ], signingKey: Data("fixture-signing-key".utf8)),
            remoteTripUpdate: remoteTripUpdate, now: { syncDate }, sleep: { _ in }, id: { syncOther })
        _ = try await source.signIn(
            PasswordSignInInput(
                email: "demo@example.com", password: "fixture-password",
                deviceID: syncOther, deviceName: "Test"))
        return source
    }

    @Test func unchangedPullIgnoresReceiptTimes() async throws {
        let store = try await SyncStore()
        let source = try await source()
        _ = try await FullPull(database: store.database, source: source, now: { syncDate }).run(epoch: store.epoch)
        let result = try await FullPull(database: store.database, source: source, now: { syncDate + 60 })
            .run(epoch: store.epoch)
        #expect(result.changes == SyncChanges())
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        #expect(try await engine.refreshNow().changes == SyncChanges())
        await engine.cancelAndWait()
        try await store.close()
    }

    @Test func mockRefreshSwitchChangesServerTripAndRevisionOnce() async throws {
        let signal = MockRefreshSignal()
        let store = try await SyncStore()
        let source = try await source(remoteTripUpdate: { await signal.consume() })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        _ = try await engine.refreshNow()
        #expect(try await engine.refreshNow().changes == SyncChanges())
        await signal.arm()
        #expect(try await engine.refreshNow().changes == SyncChanges(tripsUpdated: 1, planVersionsChanged: 1))
        #expect(try await source.fetchTrips().first?.card.flightNumber == "CF123")
        #expect(try await source.fetchTripDetail(id: syncTrip).detail.detailVersion == "refresh-CF123")
        #expect(try await engine.refreshNow().changes == SyncChanges())
        await engine.cancelAndWait()
        try await store.close()
    }

    @Test func oneTripUpdatedAndThenRemovedOnMockServer() async throws {
        let store = try await SyncStore()
        let source = try await source()
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        _ = try await engine.refreshNow()
        var updated = card()
        updated.card.flightNumber = "CF123"
        try await source.replaceRemoteTrips([updated], details: [syncTrip: detail()])
        #expect(try await engine.refreshNow().changes == SyncChanges(tripsUpdated: 1))
        try await source.replaceRemoteTrips([], details: [:])
        #expect(try await engine.refreshNow().changes == SyncChanges(tripsRemoved: 1))
        #expect(try await engine.refreshNow().changes == SyncChanges())
        try await source.replaceRemoteTrips([updated], details: [syncTrip: detail()])
        #expect(try await engine.refreshNow().changes == SyncChanges(tripsAdded: 1))
        await engine.cancelAndWait()
        try await store.close()
    }

    @Test(arguments: [false, true])
    func planHashOrDetailVersionCountsAsOneUpdatedTrip(changeHash: Bool) async throws {
        let store = try await SyncStore()
        let source = try await source()
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        _ = try await engine.refreshNow()
        let hash = changeHash ? "new-hash" : "hash"
        try await source.replaceRemoteTrips(
            [card(hash: hash, version: "v2")],
            details: [syncTrip: detail(hash, version: "v2")])
        #expect(try await engine.refreshNow().changes == SyncChanges(tripsUpdated: 1, planVersionsChanged: 1))
        #expect(try await engine.refreshNow().changes == SyncChanges())
        await engine.cancelAndWait()
        try await store.close()
    }

    @Test func downloadingOrEvictingAnUnchangedPlanIsNotAnUpdate() async throws {
        let store = try await SyncStore()
        let source = try await source()
        let pull = FullPull(database: store.database, source: source)
        _ = try await pull.run(epoch: store.epoch)
        try await source.replaceRemoteTrips([card(keep: false)], details: [syncTrip: detail()])
        #expect(try await pull.run(epoch: store.epoch).changes == SyncChanges())
        try await source.replaceRemoteTrips([card()], details: [syncTrip: detail()])
        #expect(try await pull.run(epoch: store.epoch).changes == SyncChanges())
        try await store.close()
    }

    @Test func joinedRefreshCountsAChangedTripOnceAcrossReruns() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        _ = try await engine.refreshNow()
        let gate = TestGate()
        await source.configure(
            trips: [card(version: "v2")], detail: detail(version: "v2"),
            hook: { if $0 == "identity" { await gate.block() } })
        let first = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        let second = Task { try await engine.refreshNow() }
        while await engine.waitingRefreshCount != 2 { await Task.yield() }
        await source.configure()
        await gate.release()
        #expect(try await first.value.changes == SyncChanges(tripsUpdated: 1, planVersionsChanged: 1))
        #expect(try await second.value.changes == SyncChanges(tripsUpdated: 1, planVersionsChanged: 1))
        await engine.cancelAndWait()
        try await store.close()
    }
}

private actor MockRefreshSignal {
    private var pending = false
    func arm() { pending = true }
    func consume() -> Bool {
        defer { pending = false }
        return pending
    }
}

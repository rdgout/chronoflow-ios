import AppCore
import LocalStore
import Sync
import Testing

@Suite struct PlanRetentionTests {
    @Test func leaseReferenceCountsAndPendingPreventEviction() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let retention = PlanRetention()
        let first = retention.hold(tripID: syncTrip)
        let second = retention.hold(tripID: syncTrip)
        await source.configure(trips: [card(keep: false)])
        let pull = FullPull(database: store.database, source: source, retention: retention)
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") != nil)
        first.release()
        first.release()
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") != nil)
        _ = try await store.enqueue(.checkOff(check()))
        second.release()
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") != nil)
        let row = try await OutboxRepository(database: store.database).pending().first!
        try await OutboxRepository(database: store.database).remove(id: row.id)
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") == nil)
        try await store.close()
    }
    @Test func pendingDeletedTripKeepsPlan() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let pull = FullPull(database: store.database, source: source)
        _ = try await pull.run(epoch: store.epoch)
        _ = try await store.enqueue(.checkOff(check()))
        await source.configure(trips: [])
        _ = try await pull.run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") != nil)
        try await store.close()
    }
}

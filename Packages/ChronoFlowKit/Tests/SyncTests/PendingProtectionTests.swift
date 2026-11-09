import AppCore
import GRDB
import LocalStore
import Sync
import Testing

@Suite struct PendingProtectionTests {
    @Test func protectLocalValuesEvenWhenQueuedDuringPull() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        await source.configure(hook: { method in
            guard method == "trips" else { return }
            _ = try await store.enqueue(
                .settings(section: .bodyClock, patch: JSONObject(["habitual_bed": .string("22:00")])))
            _ = try await store.enqueue(
                .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])), index: 1)
            _ = try await store.enqueue(.profile(ProfileChange(name: "Edited", email: "demo@example.com")), index: 2)
            _ = try await store.enqueue(.walkthrough, index: 3)
            _ = try await store.enqueue(.policies(version: "new"), index: 4)
            _ = try await store.enqueue(.checkOff(check()), index: 5)
        })
        _ = try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        let account = try await AccountRepository(database: store.database).account()
        #expect(account?.name == "Edited")
        #expect(account?.walkthroughSeen == true)
        let settings = try await SettingsRepository(database: store.database).settings()
        #expect(!settings.contains { $0.section == "readiness" })
        #expect(
            try settings.first { $0.section == "bodyClock" }?.value.decode(JSONObject.self)["habitualBed"]
                == .string("22:00"))
        #expect(
            try settings.first { $0.section == "preferences" }?.value.decode(JSONObject.self)["timeFormat"]
                == .string("12"))
        #expect(
            try settings.first { $0.section == "policies" }?.value.decode(JSONObject.self)["acceptedTermsVersion"]
                == .string("new"))
        #expect(
            try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").first?.status
                == "done")
        try await store.close()
    }
    @Test func queuedCompletionPreservedFromLegacyRow() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        try await OutboxRepository(database: store.database).upsert(
            OutboxRecord(
                id: "parked", kind: "complete-trip",
                payload: .encoding(JSONObject(["tripId": .string(syncTrip)])), createdAt: "1"))
        _ = try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        let trip = try await TripRepository(database: store.database).trips().first
        #expect(try trip?.card.decode(JSONObject.self)["progress"]?.object?["status"] == .string("completed"))
        try await store.close()
    }
}

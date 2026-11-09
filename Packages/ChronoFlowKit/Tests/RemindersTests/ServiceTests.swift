import AppCore
import Foundation
import LocalStore
import PlanCore
import Testing

@testable import Reminders

func eventually(_ condition: @Sendable () async throws -> Bool) async throws {
    for _ in 0..<2000 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(try await condition())
}

@Suite struct ReminderServiceTests {
    @Test func fakeCenterCapsAt60AndKeepsUnchangedRequests() async throws {
        let store = try await ReminderTestStore()
        for index in 0..<11 {
            try await store.store(
                reminderPlan((0..<6).map { reminderBlock(Double($0 * 3 + 1), ordinal: $0 + 1) }, id: "trip-\(index)"))
        }
        let center = FakeReminderCenter()
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.pending().count == 60 }
        await service.reschedule()
        #expect(await center.adds.count == 60)
        #expect(try await ReminderLedger.read(database: store.database).count == 60)
        await service.detach()
        try await store.close()
    }

    @Test func replaceRemovePermissionAndFailures() async throws {
        let store = try await ReminderTestStore()
        try await store.store(
            reminderPlan([reminderBlock(), reminderBlock(2, ordinal: 2), reminderBlock(3, ordinal: 3)]))
        let center = FakeReminderCenter()
        await center.reject(reminderBlock(2).id)
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.pending().count == 2 }
        await service.reschedule()
        #expect(await center.adds.count == 2)
        let before = await center.pending()
        try await SettingsRepository(database: store.database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings(leadMin: 60))))
        try await eventually { await center.pending().count == 1 }
        #expect(await center.pending().first?.sendAt == reminderNow.addingTimeInterval(2 * 3600))
        let removed = try #require(before.first { $0.blockID == reminderBlock().id })
        #expect(await center.removals.contains(removed.identifier))
        await center.setPermission(.blocked)
        await service.reschedule()
        #expect(await center.pending().isEmpty)
        await center.setPermission(.granted)
        await service.reschedule()
        #expect(await center.pending().count == 1)
        try await SettingsRepository(database: store.database).remove(section: "reminders")
        try await eventually { await center.pending().isEmpty }
        await service.detach()
        try await store.close()
    }

    @Test func overlappingRequestsRerunWithLatestSettings() async throws {
        let store = try await ReminderTestStore()
        try await store.store(reminderPlan([reminderBlock(2), reminderBlock(3, ordinal: 2)]))
        let center = FakeReminderCenter()
        await center.holdNext()
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.adding }
        try await SettingsRepository(database: store.database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings(leadMin: 60))))
        let first = Task { await service.reschedule() }
        let second = Task { await service.reschedule() }
        await Task.yield()
        await center.release()
        await first.value
        await second.value
        await service.reschedule()
        #expect(await center.maximumConcurrentAdds == 1)
        #expect(
            await center.pending().map(\.sendAt).sorted() == [
                reminderNow.addingTimeInterval(3600), reminderNow.addingTimeInterval(7200),
            ])
        await service.detach()
        try await store.close()
    }

    @Test func serializedRerunAndSignOutDrain() async throws {
        let store = try await ReminderTestStore()
        try await store.store(reminderPlan([reminderBlock(), reminderBlock(2, ordinal: 2)]))
        let center = FakeReminderCenter()
        await center.holdNext()
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.adding }
        let rerun = Task { await service.reschedule() }
        let wipe = Task { await service.detach() }
        await Task.yield()
        await center.release()
        await rerun.value
        await wipe.value
        #expect(await center.pending().isEmpty)
        #expect(try await ReminderLedger.read(database: store.database).isEmpty)
        try await store.close()
    }

    @Test func checkOffUndoDisabledAndRelaunchLedger() async throws {
        let store = try await ReminderTestStore()
        let value = reminderPlan([reminderBlock(), reminderBlock(1.1, type: .avoidLight)])
        try await store.store(value)
        let center = FakeReminderCenter()
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.pending().count == 1 }
        let request = try #require(await center.pending().first)
        try await OutboxRepository(database: store.database).enqueue(
            .checkOff(
                CheckOffChange(
                    tripID: "trip", planInputHash: "hash", type: .seekLight, localDate: "2026-10-14", ordinal: 1,
                    status: .done)))
        try await eventually { await center.pending().first?.memberKeys.count == 1 }
        try await OutboxRepository(database: store.database).enqueue(
            .checkOff(
                CheckOffChange(
                    tripID: "trip", planInputHash: "hash", type: .seekLight, localDate: "2026-10-14", ordinal: 1,
                    status: nil)))
        try await eventually { await center.pending().first?.memberKeys.count == 2 }
        try await OutboxRepository(database: store.database).enqueue(
            .settings(
                section: .reminders,
                patch: JSONObject([
                    "light": .bool(false), "avoid": .bool(false), "caffeine": .bool(false), "winddown": .bool(false),
                ])))
        try await eventually { await center.pending().isEmpty }
        // A delivered merged row survives a new scheduler and a disabled-permission interval.
        let ledger = [
            ReminderLedgerEntry(
                tripId: "trip", inputHash: "hash", sendAtMs: request.sendAt.timeIntervalSince1970 * 1000,
                memberKeys: request.memberKeys)
        ]
        await service.detach()
        try await ReminderLedger.write(ledger, database: store.database)
        try await SettingsRepository(database: store.database).upsert(
            SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        let relaunched = ReminderService(center: center, now: { request.sendAt.addingTimeInterval(1) })
        await relaunched.attach(database: store.database)
        await relaunched.reschedule()
        #expect(await center.pending().isEmpty)
        await service.detach()
        await relaunched.detach()
        try await store.close()
    }

    @Test func currentOfflinePlansOnlyAndAccountSwitchClears() async throws {
        let store = try await ReminderTestStore()
        try await store.store(reminderPlan())
        var trip = try #require(try await TripRepository(database: store.database).trips().first)
        let center = FakeReminderCenter()
        let service = ReminderService(center: center, now: { reminderNow })
        await service.attach(database: store.database)
        try await eventually { await center.pending().count == 1 }
        trip.currentInputHash = "changed"
        try await TripRepository(database: store.database).upsert(trip)
        try await eventually { await center.pending().isEmpty }
        trip.currentInputHash = "hash"
        trip.keepOffline = false
        try await TripRepository(database: store.database).upsert(trip)
        await service.reschedule()
        #expect(await center.pending().isEmpty)
        trip.keepOffline = true
        trip.deletedAt = reminderNow.ISO8601Format()
        try await TripRepository(database: store.database).upsert(trip)
        await service.reschedule()
        #expect(await center.pending().isEmpty)
        trip.deletedAt = nil
        try await TripRepository(database: store.database).upsert(trip)
        try await eventually { await center.pending().count == 1 }
        let next = try await ReminderTestStore()
        await service.attach(database: next.database)
        await service.reschedule()
        #expect(await center.pending().isEmpty)
        #expect(try await ReminderLedger.read(database: store.database).isEmpty)
        await service.detach()
        try await store.close()
        try await next.close()
    }
}

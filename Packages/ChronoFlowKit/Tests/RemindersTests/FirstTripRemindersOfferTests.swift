import AppCore
import LocalStore
import Reminders
import Testing

@Suite struct FirstTripRemindersOfferTests {
    @Test(arguments: ReminderPermission.allCases, [true, false])
    func permissionAndEnabledKindsGateTheOneTimeOffer(permission: ReminderPermission, enabled: Bool) async throws {
        let store = try await ReminderTestStore()
        let settings = SettingsRepository(database: store.database)
        try await settings.upsert(
            SettingsRecord(
                section: "reminders",
                value: .encoding(ReminderSettings(light: false, avoid: false, caffeine: enabled, winddown: false))))
        let offer = FirstTripRemindersOffer(database: store.database)
        #expect(try await offer.consume(permission: permission) == false)
        try await offer.queue(firstTrip: false)
        #expect(try await offer.consume(permission: permission) == false)
        try await offer.queue(firstTrip: true)
        #expect(try await offer.consume(permission: permission) == (permission == .undetermined && enabled))
        try await offer.queue(firstTrip: true)
        #expect(try await offer.consume(permission: .undetermined) == false)
        try await store.close()
    }

    @Test func missingSettingsWaitWithoutConsumingTheOffer() async throws {
        let store = try await ReminderTestStore()
        let settings = SettingsRepository(database: store.database)
        try await settings.remove(section: "reminders")
        let offer = FirstTripRemindersOffer(database: store.database)
        try await offer.queue(firstTrip: true)
        #expect(try await offer.consume(permission: .undetermined) == nil)
        try await settings.upsert(SettingsRecord(section: "reminders", value: .encoding(ReminderSettings())))
        #expect(try await offer.consume(permission: .undetermined) == true)
        try await store.close()
    }

    @Test func pendingAndSeenSurviveReopeningAndDuplicateSaveCompletion() async throws {
        let store = try await ReminderTestStore()
        try await FirstTripRemindersOffer(database: store.database).queue(firstTrip: true)
        try await store.database.close()
        try await store.database.open(accountID: reminderAccount)
        let recovered = FirstTripRemindersOffer(database: store.database)
        async let first = recovered.consume(permission: .undetermined)
        async let duplicate = recovered.consume(permission: .undetermined)
        let results = try await [first, duplicate]
        #expect(results.filter { $0 == true }.count == 1)
        try await store.database.close()
        try await store.database.open(accountID: reminderAccount)
        let shown = FirstTripRemindersOffer(database: store.database)
        try await shown.queue(firstTrip: true)
        #expect(try await shown.consume(permission: .undetermined) == false)
        try await store.close()
    }

    @Test func anotherAccountDoesNotConsumeThePendingOffer() async throws {
        let first = try await ReminderTestStore()
        let other = try await ReminderTestStore(accountID: "01900000-0000-7000-8000-000000000002")
        try await FirstTripRemindersOffer(database: first.database).queue(firstTrip: true)
        #expect(try await FirstTripRemindersOffer(database: other.database).consume(permission: .undetermined) == false)
        #expect(try await FirstTripRemindersOffer(database: first.database).consume(permission: .undetermined) == true)
        try await first.close()
        try await other.close()
    }
}

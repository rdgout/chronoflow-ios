import AppCore
import Foundation
import GRDB
import LocalStore
import Testing

@Suite struct LocalMutationsTests {
    @Test func durableRestartAndRollback() async throws {
        let store = try await SyncStore()
        let row = try await store.enqueue(.checkOff(check()))
        #expect((UUID(uuidString: row.id)?.uuid.6 ?? 0) >> 4 == 7)
        try await store.database.close()
        try await store.database.open(accountID: syncAccount)
        #expect(try await OutboxRepository(database: store.database).pending() == [row])
        #expect(
            try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").first?.status
                == "done")
        await #expect(throws: (any Error).self) { try await store.enqueue(.checkOff(check(status: .skipped))) }
        #expect(
            try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").first?.status
                == "done")
        try await store.close()
    }
    @Test func supportedValuesAndSensitiveInputs() async throws {
        let store = try await SyncStore()
        _ = try await store.enqueue(.settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])))
        _ = try await store.enqueue(.profile(ProfileChange(name: "Edited", email: "demo@example.com")), index: 1)
        _ = try await store.enqueue(.walkthrough, index: 2)
        try await SettingsRepository(database: store.database).upsert(
            SettingsRecord(
                section: "policies", value: .encoding(AccountPolicies(termsVersion: "1", privacyVersion: "1"))))
        _ = try await store.enqueue(.policies(version: "1"), index: 3)
        #expect(try await AccountRepository(database: store.database).account()?.name == "Edited")
        #expect(try await AccountRepository(database: store.database).account()?.walkthroughSeen == true)
        let settings = try await SettingsRepository(database: store.database).settings()
        #expect(
            try settings.first { $0.section == "preferences" }?.value.decode(JSONObject.self)["timeFormat"]
                == .string("12"))
        for key in ["password", "token", "recovery_code", "signature", "current_password"] {
            await #expect(throws: LocalMutationFailure.invalidPayload) {
                try await store.enqueue(.settings(section: .preferences, patch: JSONObject([key: .string("secret")])))
            }
        }
        await #expect(throws: LocalMutationFailure.invalidPayload) {
            try await store.enqueue(
                .settings(
                    section: .bodyClock, patch: JSONObject(["habitual_bed": .object(["token": .string("secret")])])))
        }
        await #expect(throws: LocalMutationFailure.onlineOnly) {
            try await store.enqueue(.profile(ProfileChange(name: "Other", email: "different@example.com")), index: 4)
        }
        await #expect(throws: LocalMutationFailure.unsupported) {
            try await store.enqueue(.unsupported(kind: .security, payload: JSONObject()))
        }
        #expect(try await OutboxRepository(database: store.database).pending().count == 4)
        try await store.close()
    }
}

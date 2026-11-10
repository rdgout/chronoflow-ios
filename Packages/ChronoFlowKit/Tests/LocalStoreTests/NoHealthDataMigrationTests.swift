import AppCore
import Foundation
import GRDB
import Testing

@testable import LocalStore

struct NoHealthDataMigrationTests {
    @Test func upgradePurgesStoredHealthAnswersAndPendingWritesAndInvalidatesAffectedRecovery() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        try await store.open(accountID: accountA)
        try await store.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='v2-no-health-data'")
            let body = JSONObject([
                "ageBand": .string("18_64"), "shiftWork": .null, "habitualBed": .string("23:00"),
                "bipolar": .bool(false), "eyeDisease": .bool(true), "pregnancy": .null, "vte": .bool(true),
                "sleepPhaseDisorder": .bool(false), "oralContraception": .bool(true), "caffeineRuledOut": .bool(true),
                "invalidDrafts": .object(["pregnancy": .bool(false), "habitual_bed": .string("bad")]),
            ])
            try SettingsRecord(section: "bodyClock", value: .encoding(body)).save(db)
            try SettingsRecord(
                section: "readiness", value: .encoding(JSONObject(["lightDevicesAllowed": .bool(false)]))
            ).save(db)
            for (id, patch) in [
                (
                    "mixed",
                    JSONObject(["bipolar": .bool(false), "caffeine_ruled_out": .bool(true), "shift_work": .bool(false)])
                ),
                ("medical-only", JSONObject(["vte": .bool(true), "oral_contraception": .bool(false)])),
            ] {
                try OutboxRecord(
                    id: id, kind: "settings",
                    payload: .encoding(
                        JSONObject([
                            "section": .string("bodyClock"), "patch": .object(patch.fields),
                        ])), createdAt: "2026-11-10T10:00:00Z"
                ).insert(db)
            }
            try TripRecord(id: "trip", card: .encoding(JSONObject()), departureUtc: "2026-11-10T10:00:00Z").insert(db)
            try PlanVersionRecord(
                tripId: "trip", inputHash: "hash",
                detail: .encoding(
                    JSONObject([
                        "futureField": .object(["keep": .string("value"), "pregnancy": .bool(false)]),
                        "prompts": .array([.object(["kind": .string("screening"), "question": .string("bipolar")])]),
                    ])), receivedAt: "2026-11-10T10:00:00Z"
            ).insert(db)
            try DraftRecord(
                id: "member-wizard", form: .encoding(JSONObject()),
                wizardState: .encoding(JSONObject(["profile": .object(["pregnancy": .bool(false)])])),
                updatedAt: "2026-11-10T10:00:00Z"
            ).insert(db)
            try DraftRecord(id: "clean", form: .encoding(JSONObject()), updatedAt: "2026-11-10T10:00:00Z").insert(db)
        }
        try await store.close()
        try await store.open(accountID: accountA)
        let body = try await store.read {
            try SettingsRecord.fetchOne($0, key: "bodyClock")!.value.decode(JSONObject.self)
        }
        for key in [
            "bipolar", "eyeDisease", "pregnancy", "vte", "sleepPhaseDisorder", "oralContraception", "caffeineRuledOut",
        ] {
            #expect(body[key] == nil)
        }
        #expect(body["excludeCaffeine"] == .bool(true) && body["flightMovementBreaks"] == .bool(false))
        #expect(body["ageBand"] == .string("18_64") && body["shiftWork"] == .null)
        #expect(body["invalidDrafts"]?.object == ["habitual_bed": .string("bad")])
        #expect(try await store.read { try SettingsRecord.fetchOne($0, key: "readiness") } == nil)
        let rows = try await OutboxRepository(database: store).pending()
        #expect(rows.count == 1)
        #expect(
            try rows.first?.payload.decode(JSONObject.self)["patch"]?.object == [
                "exclude_caffeine": .bool(true), "shift_work": .bool(false),
            ])
        let plan = try await store.read { try PlanVersionRecord.fetchOne($0)?.detail.decode(JSONObject.self) }
        #expect(plan?["futureField"] == .object(["keep": .string("value")]))
        #expect(plan?["prompts"] == .array([]))
        #expect(try await store.read { try DraftRecord.fetchOne($0, key: "member-wizard") } == nil)
        #expect(try await store.read { try DraftRecord.fetchOne($0, key: "clean") } != nil)
        try await store.close()
        try await store.open(accountID: accountA)
        #expect(
            try await store.read { try SettingsRecord.fetchOne($0, key: "bodyClock")!.value.decode(JSONObject.self) }
                == body)
        try await store.close()
    }
}

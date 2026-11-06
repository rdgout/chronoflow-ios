import Foundation
import GRDB
import Testing

@testable import LocalStore

struct RecordsTests {
    @Test func allRecordsRoundTripUnknownJSONNullsAndCompositeKeys() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        try await store.open(accountID: accountA)
        let json = try JSONDocument(
            #"{"future":{"big":123456789012345678901234567890,"list":[null,true,"é"]},"n":1.000}"#)
        let account = AccountRecord(
            id: accountA, name: "Dutch ' name", email: "a@example.test", hasVerifiedEmail: false)
        let trip = TripRecord(
            id: "trip'", card: json, adaptation: json, form: json, revision: json,
            currentInputHash: "hash", keepOffline: true, departureUtc: "date", planStartUtc: "start",
            planStartZone: "Europe/Amsterdam", preparationDays: 2, planEndUtc: "end",
            planEndDate: "day", deletedAt: "deleted", deletedLocally: true)
        let plan = PlanVersionRecord(
            tripId: trip.id, inputHash: "hash", detail: json, receivedAt: "date", detailVersion: "v")
        let mark = CheckMarkRecord(
            tripId: trip.id, inputHash: "hash", type: "sleep", localDate: "date", ordinal: 0,
            status: "done", markedAt: "date")
        let settings = SettingsRecord(section: "futureSection", value: json)
        let draft = DraftRecord(
            id: "draft", tripId: trip.id, form: json, baseForm: json, dirty: false, review: json,
            token: nil, inputRevision: 5, reviewRevision: 4, wizardSourceRevision: "r",
            wizardReview: json, furthestStep: "sleep", wizardState: json, sourceRevision: json,
            saveFailure: json, fieldErrors: json, updatedAt: "now")
        let outbox = OutboxRecord(
            id: "id", kind: "futureKind", payload: json, createdAt: "now", attempts: 2, lastError: "offline")
        try await store.write { db in
            try account.insert(db)
            try trip.insert(db)
            try plan.insert(db)
            try mark.insert(db)
            try settings.insert(db)
            try draft.insert(db)
            try outbox.insert(db)
        }
        try await store.read { db throws -> Void in
            #expect(try AccountRecord.fetchOne(db) == account)
            #expect(try TripRecord.fetchOne(db) == trip)
            #expect(try PlanVersionRecord.fetchOne(db) == plan)
            #expect(try CheckMarkRecord.fetchOne(db) == mark)
            #expect(try SettingsRecord.fetchOne(db) == settings)
            #expect(try DraftRecord.fetchOne(db) == draft)
            #expect(try OutboxRecord.fetchOne(db) == outbox)
            #expect(try String.fetchOne(db, sql: "SELECT card FROM trips") == json.rawValue)
        }
        let other = CheckMarkRecord(
            tripId: trip.id, inputHash: "hash", type: "sleep", localDate: "date", ordinal: 1,
            status: "skipped", markedAt: "later")
        try await TripRepository(database: store).store(plan: plan, checks: [other])
        #expect(try await TripRepository(database: store).checks(tripID: trip.id, inputHash: "hash") == [mark, other])
        let nullable = TripRecord(id: "nullable", card: try JSONDocument("null"), departureUtc: "later")
        try await TripRepository(database: store).upsert(nullable)
        #expect(try await TripRepository(database: store).trips().contains(nullable))
        let emptyDraft = DraftRecord(id: "empty", form: json, updatedAt: "later")
        try await DraftRepository(database: store).upsert(emptyDraft)
        #expect(try await DraftRepository(database: store).drafts().contains(emptyDraft))
        #expect(try JSONDecoder().decode(TripRecord.self, from: JSONEncoder().encode(nullable)) == nullable)
        try await store.close()
    }

    @Test func invalidJSONCannotEnterARecord() throws {
        #expect(throws: (any Error).self) { try JSONDocument("{bad") }
        #expect(try JSONDocument("[null,1,{}]").rawValue == "[null,1,{}]")
    }

    @Test func repositoriesBindKeysAndOrderOutboxByTimestampThenID() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        try await store.open(accountID: accountA)
        let repository = OutboxRepository(database: store)
        for id in ["b", "a", "c"] {
            try await repository.upsert(
                OutboxRecord(id: id, kind: "settings", payload: JSONDocument("{}"), createdAt: id == "c" ? "0" : "1"))
        }
        #expect(try await repository.pending().map(\.id) == ["c", "a", "b"])
        try await repository.remove(id: "' OR 1=1 --")
        #expect(try await repository.pending().count == 3)
        try await repository.remove(id: "a")
        #expect(try await repository.pending().map(\.id) == ["c", "b"])
        let settings = SettingsRepository(database: store)
        try await settings.upsert(SettingsRecord(section: "preferences", value: JSONDocument("{}")))
        try await settings.remove(section: "preferences")
        #expect(try await settings.settings().isEmpty)
        let drafts = DraftRepository(database: store)
        try await drafts.upsert(DraftRecord(id: "draft", form: JSONDocument("{}"), updatedAt: "now"))
        try await drafts.remove(id: "draft")
        #expect(try await drafts.drafts().isEmpty)
        try await store.close()
    }
}

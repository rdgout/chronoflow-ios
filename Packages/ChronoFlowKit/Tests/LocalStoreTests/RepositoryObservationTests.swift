import Foundation
import GRDB
import Testing

@testable import LocalStore

struct RepositoryObservationTests {
    @Test func initialFetchIsOffMainAndValuesAppearAfterAtomicCommitOnly() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountDatabase(applicationSupport: root)
        try await store.open(accountID: accountA)
        let values = try await store.observe { db -> AccountRecord? in
            #expect(!Thread.isMainThread)
            return try AccountRecord.fetchOne(db)
        }
        var iterator = values.makeAsyncIterator()
        let initial = try await iterator.next()
        #expect(initial != nil)
        #expect(initial! == nil)
        let final = AccountRecord(id: accountA, name: "complete", email: "new@example.test")
        try await store.write { db in
            try AccountRecord(id: accountA, name: "half", email: "old").save(db)
            try final.save(db)
        }
        #expect(try await iterator.next() == final)
        await #expect(throws: StoreFailure.unavailable) {
            try await store.write { db in
                try AccountRecord(id: accountA, name: "rolled back", email: "bad").save(db)
                throw StoreFailure.unavailable
            }
        }
        try await store.close()
        #expect(try await iterator.next() == nil)
    }

    @Test func cancellationAndCloseEndSubscriptionsBeforeAnotherAccountOpens() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = AccountDatabase(applicationSupport: root)
        try await first.open(accountID: accountA)
        let values = try await TripRepository(database: first).values()
        let (received, continuation) = AsyncStream<[TripRecord]>.makeStream()
        let consumer = Task {
            do {
                for try await value in values { continuation.yield(value) }
                continuation.finish()
            } catch { continuation.finish() }
        }
        var iterator = received.makeAsyncIterator()
        #expect(await iterator.next() == [])
        consumer.cancel()
        await consumer.value
        try await TripRepository(database: first).upsert(
            TripRecord(id: "late", card: JSONDocument("{}"), departureUtc: "date"))
        try await first.close()
        #expect(await iterator.next() == nil)
        #expect(await first.observationCount == 0)
        let second = AccountDatabase(applicationSupport: root)
        try await second.open(accountID: accountB)
        #expect(try await TripRepository(database: second).trips().isEmpty)
        try await second.close()
    }

    @Test @MainActor func accountModelSeparatesUnknownEmptyAndLoadedAndClearsOnDetach() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: accountA)
        let model = AccountModel()
        #expect(model.state == .unknown)
        let repo = AccountRepository(database: database)
        await model.attach(to: repo, epoch: 10)
        await waitForModel(model) { $0 == .loaded(nil) }
        let account = AccountRecord(id: accountA, name: "Name", email: "email")
        try await repo.upsert(account)
        await waitForModel(model) { $0 == .loaded(account) }
        await model.detach()
        #expect(model.state == .unknown)
        try await repo.upsert(AccountRecord(id: accountA, name: "late", email: "late"))
        try await database.close()
        #expect(model.state == .unknown)
    }

    @Test func everyRepositoryEmitsInitialEmptyAndCommittedValues() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: accountA)
        let trips = TripRepository(database: database)
        let settings = SettingsRepository(database: database)
        let drafts = DraftRepository(database: database)
        let outbox = OutboxRepository(database: database)
        var plans = try await trips.planValues(tripID: "trip", inputHash: "hash").makeAsyncIterator()
        var checks = try await trips.checkValues(tripID: "trip", inputHash: "hash").makeAsyncIterator()
        var sections = try await settings.values().makeAsyncIterator()
        var draftValues = try await drafts.values().makeAsyncIterator()
        var pending = try await outbox.values().makeAsyncIterator()
        let missingPlan = try await plans.next()
        #expect(missingPlan != nil)
        #expect(missingPlan! == nil)
        #expect(try await checks.next() == [])
        #expect(try await sections.next() == [])
        #expect(try await draftValues.next() == [])
        #expect(try await pending.next() == [])
        let json = try JSONDocument("{}")
        try await trips.upsert(TripRecord(id: "trip", card: json, departureUtc: "date"))
        let plan = PlanVersionRecord(tripId: "trip", inputHash: "hash", detail: json, receivedAt: "date")
        let mark = CheckMarkRecord(
            tripId: "trip", inputHash: "hash", type: "sleep", localDate: "date", ordinal: 0,
            status: "done", markedAt: "date")
        try await trips.store(plan: plan, checks: [mark])
        #expect(try await plans.next() == plan)
        #expect(try await checks.next() == [mark])
        let section = SettingsRecord(section: "preferences", value: json)
        try await settings.upsert(section)
        #expect(try await sections.next() == [section])
        let draft = DraftRecord(id: "draft", form: json, updatedAt: "date")
        try await drafts.upsert(draft)
        #expect(try await draftValues.next() == [draft])
        let change = OutboxRecord(id: "change", kind: "settings", payload: json, createdAt: "date")
        try await outbox.upsert(change)
        #expect(try await pending.next() == [change])
        try await database.close()
        #expect(try await plans.next() == nil)
        #expect(try await checks.next() == nil)
        #expect(try await sections.next() == nil)
        #expect(try await draftValues.next() == nil)
        #expect(try await pending.next() == nil)
    }

    @Test @MainActor func modelRejectsOlderAccountAfterReplacementAndSurfacesStoreFailure() async throws {
        let root = try temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = AccountDatabase(applicationSupport: root)
        let second = AccountDatabase(applicationSupport: root)
        try await first.open(accountID: accountA)
        try await second.open(accountID: accountB)
        let a = AccountRecord(id: accountA, name: "A", email: "a")
        let b = AccountRecord(id: accountB, name: "B", email: "b")
        try await AccountRepository(database: first).upsert(a)
        try await AccountRepository(database: second).upsert(b)
        let model = AccountModel()
        await model.attach(to: AccountRepository(database: first), epoch: 1)
        await waitForModel(model) { $0 == .loaded(a) }
        await model.attach(to: AccountRepository(database: second), epoch: 2)
        await waitForModel(model) { $0 == .loaded(b) }
        try await AccountRepository(database: first).upsert(AccountRecord(id: accountA, name: "late", email: "late"))
        try await first.close()
        #expect(model.state == .loaded(b))
        await model.detach()
        try await second.close()
        await model.attach(to: AccountRepository(database: second), epoch: 3)
        await waitForModel(model) { $0 == .failed }
        await model.detach()
    }

    @MainActor private func waitForModel(_ model: AccountModel, matches: (AccountModel.LoadState) -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !matches(model.state), ContinuousClock.now < deadline { await Task.yield() }
        #expect(matches(model.state))
    }
}

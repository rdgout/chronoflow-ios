import AppCore
import GRDB
import LocalStore
import Sync
import Testing

@Suite struct OutboxFlusherTests {
    @Test func fifoDependencyBlockingAndParkedKinds() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let first = try await store.enqueue(
            .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])))
        _ = try await store.enqueue(
            .settings(section: .preferences, patch: JSONObject(["time_format": .string("24")])), index: 1)
        _ = try await store.enqueue(.walkthrough, index: 2)
        for (index, kind) in [OutboxKind.completeTrip, .security, .dataExport].enumerated() {
            try await OutboxRepository(database: store.database).upsert(
                OutboxRecord(
                    id: "parked\(index)", kind: kind.rawValue,
                    payload: .encoding(JSONObject(["tripId": .string(syncTrip)])), createdAt: first.createdAt))
        }
        await source.configure(failures: [.server(status: 500), nil])
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(await source.changes.count == 2)
        #expect(try await source.changes.first == first.change)
        #expect(result.retryAfter == 1)
        #expect(result.parked == 3)
        let rows = try await OutboxRepository(database: store.database).pending()
        #expect(rows.count == 5)
        #expect(rows.first?.attempts == 1)
        #expect(rows.first?.lastError == "server")
        try await store.close()
    }
    @Test(arguments: [
        (DataFailure.server(status: 400), true, 0, nil as String?),
        (.validation(fields: ["name": FieldMessage(key: "secret response")], status: 422), true, 0, nil),
        (.server(status: 403), true, 0, nil), (.server(status: 404), true, 0, nil),
        (.server(status: 408), false, 1, "server"), (.server(status: 425), false, 1, "server"),
        (.throttled(retryAfterSeconds: 900, status: 429), false, 1, "throttled"),
        (.server(status: 500), false, 1, "server"), (.offline, false, 1, "offline"),
        (.unauthorized(status: 401), false, 0, nil), (.emailUnverified(status: 403), false, 0, nil),
    ])
    func failureClassification(_ failure: DataFailure, final: Bool, attempts: Int, lastError: String?) async throws {
        let store = try await SyncStore()
        _ = try await store.enqueue(.walkthrough)
        let source = ScriptedSource()
        await source.configure(failures: [failure])
        let flusher = OutboxFlusher(database: store.database, source: source, now: { syncDate })
        if case .unauthorized = failure {
            await #expect(throws: failure) { try await flusher.run(epoch: store.epoch) }
        } else if case .emailUnverified = failure {
            await #expect(throws: failure) { try await flusher.run(epoch: store.epoch) }
        } else {
            let result = try await flusher.run(epoch: store.epoch)
            #expect(result.refusals.count == (final ? 1 : 0))
            if case .throttled = failure { #expect(result.retryAfter == 900) }
        }
        let pending = try await OutboxRepository(database: store.database).pending()
        #expect(pending.count == (final ? 0 : 1))
        if !final {
            #expect(pending.first?.attempts == attempts)
            #expect(pending.first?.lastError == lastError)
        }
        let settings = try await SettingsRepository(database: store.database).settings()
        #expect(settings.contains { $0.section == "syncFailure" } == final)
        #expect(!String(describing: settings).contains("secret response"))
        try await store.close()
    }
    @Test(arguments: [
        (DataFailure.server(status: 400), true),
        (.validation(fields: ["name": FieldMessage(key: "invalid")], status: 422), true),
        (.server(status: 403), true), (.server(status: 404), true),
        (.server(status: 408), false), (.server(status: 425), false),
        (.throttled(retryAfterSeconds: 900, status: 429), false),
        (.server(status: 500), false), (.offline, false),
        (.unauthorized(status: 401), false), (.emailUnverified(status: 403), false),
    ])
    func policyClassification(_ failure: DataFailure, final: Bool) {
        #expect(OutboxFailurePolicy.isFinal(failure) == final)
    }
    @Test func responseRollbackReplaysAbsoluteWrite() async throws {
        let store = try await SyncStore()
        _ = try await store.enqueue(.profile(ProfileChange(name: "Edited", email: "demo@example.com")))
        let source = ScriptedSource()
        await source.configure(receipts: [.identity(identity(syncOther))])
        let first = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(first.retryAfter != nil)
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        await source.configure(receipts: [.identity(identity())])
        _ = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(await source.changes.count == 2)
        #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        try await store.close()
    }
}

extension OutboxFlusherTests {
    @Test func repeatedProfileRefusalRestoresLastAcceptedName() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.profile(ProfileChange(name: "First", email: "demo@example.com")))
        _ = try await store.enqueue(.profile(ProfileChange(name: "Second", email: "demo@example.com")), index: 1)
        await source.configure(failures: [.server(status: 422), .server(status: 422)])
        _ = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(try await AccountRepository(database: store.database).account()?.name == "Local")
        try await store.close()
    }
}

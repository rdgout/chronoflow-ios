import AppCore
import GRDB
import LocalStore
import Sync
import Testing

@Suite struct CheckOffReconcilerTests {
    @Test(arguments: [true, false]) func stableRekeyOrDisappearedStep(_ exists: Bool) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let row = try await store.enqueue(.checkOff(check("old")))
        await source.configure(detail: detail(blocks: exists))
        let reconciler = CheckOffReconciler(pull: FullPull(database: store.database, source: source))
        let result = try await reconciler.prepare(row, epoch: store.epoch)
        if exists {
            #expect(try result?.change == .checkOff(check()))
            #expect(
                try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").first?
                    .status == "done")
        } else {
            #expect(result == nil)
            #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        }
        try await store.close()
    }
    @Test func newerLocalClearSurvivesOldHashRekeyAndReceipt() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let old = try await store.enqueue(.checkOff(check("old")))
        _ = try await store.enqueue(.checkOff(check(status: nil)), index: 1)
        let reconciler = CheckOffReconciler(pull: FullPull(database: store.database, source: source))
        _ = try await reconciler.prepare(old, epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").isEmpty)
        await source.configure(
            receipts: [
                .checks(
                    TripCheckResult(
                        checkState: CheckState(
                            planInputHash: "hash",
                            marks: [
                                CheckMark(
                                    key: CheckKey(type: .sleep, localDate: "2026-11-10", ordinal: 1), status: .done,
                                    markedAt: "later")
                            ], days: []), detailVersion: "v2"))
            ],
            hook: { method in
                if method == "send" { store.epoch.invalidate() }
            })
        await #expect(throws: CancellationError.self) {
            try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        }
        #expect(try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").isEmpty)
        try await store.close()
    }
    @Test func receiptCannotReplaceNewerMarkQueuedWhileSending() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check()))
        let receipt = TripCheckResult(
            checkState: CheckState(
                planInputHash: "hash",
                marks: [
                    CheckMark(
                        key: CheckKey(type: .sleep, localDate: "2026-11-10", ordinal: 1), status: .done,
                        markedAt: "remote")
                ], days: []), detailVersion: "v2")
        await source.configure(
            receipts: [.checks(receipt)],
            hook: { method in
                if method == "send" { _ = try await store.enqueue(.checkOff(check(status: nil)), index: 1) }
            })
        _ = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").isEmpty)
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        try await store.close()
    }
    @Test func staleResponseRefreshesOnceAndThenDefers() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check()))
        await source.configure(failures: [.conflict(status: 409), .conflict(status: 409)])
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.retryAfter == 1)
        #expect(await source.calls == ["send", "detail", "send"])
        #expect(try await OutboxRepository(database: store.database).pending().first?.attempts == 1)
        await source.configure(failures: [.conflict(status: 409), .conflict(status: 409)])
        let retry = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(retry.retryAfter == 2)
        #expect(try await OutboxRepository(database: store.database).pending().first?.attempts == 2)
        try await store.close()
    }
    @Test func malformedDetailCannotProveStepDisappeared() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check("old")))
        var malformed = detail()
        malformed.plan["blocks"] = nil
        await source.configure(detail: malformed)
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.retryAfter != nil)
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        #expect(await source.changes.isEmpty)
        try await store.close()
    }
    @Test func detail404ResolvesRefusalWithoutSpin() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check("old")))
        await source.configure(failMethod: "detail", methodFailure: .server(status: 404))
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.refusals.count == 1)
        #expect(result.retryAfter == nil)
        #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        try await store.close()
    }
}

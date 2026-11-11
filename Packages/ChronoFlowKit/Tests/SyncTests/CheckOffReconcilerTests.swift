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
    @Test(arguments: [
        DataFailure.conflict(status: 409),
        .validation(fields: ["plan_input_hash": FieldMessage(key: "invalid hash")], status: 422),
        .validation(
            fields: ["form": FieldMessage(key: "This plan has changed. Refresh it before marking this step.")],
            status: 422),
    ])
    func staleResponseRefreshesOnceAndThenDefers(_ failure: DataFailure) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check()))
        await source.configure(failures: [failure, failure])
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.retryAfter == 1)
        #expect(result.refusals.isEmpty)
        #expect(await source.calls == ["send", "detail", "send"])
        let pending = try await OutboxRepository(database: store.database).pending()
        #expect(pending.count == 1)
        #expect(pending.first?.attempts == 1)
        #expect(pending.first?.lastError == (failure.status == 409 ? "conflict" : "validation"))
        #expect(
            try await SettingsRepository(database: store.database).settings().allSatisfy { $0.section != "syncFailure" }
        )
        await source.configure(failures: [failure, failure])
        let retry = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(retry.retryAfter == 2)
        #expect(retry.refusals.isEmpty)
        #expect(await source.calls == ["send", "detail", "send", "send", "detail", "send"])
        #expect(
            try await SettingsRepository(database: store.database).settings().allSatisfy { $0.section != "syncFailure" }
        )
        #expect(try await OutboxRepository(database: store.database).pending().first?.attempts == 2)
        try await store.close()
    }
    @Test func nonStaleValidationRefusesCheckOff() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        try await TripRepository(database: store.database).store(
            plan: PlanVersionRecord(
                tripId: syncTrip, inputHash: "hash", detail: .encoding(detail()),
                receivedAt: syncDate.ISO8601Format(), detailVersion: "v1"), checks: [])
        let row = try await store.enqueue(.checkOff(check()))
        await source.configure(failures: [
            .validation(fields: ["status": FieldMessage(key: "invalid status")], status: 422)
        ])
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(await source.calls == ["send"])
        #expect(result.refusals.map(\.id) == [row.id])
        #expect(result.refusals.first?.status == 422)
        #expect(result.refusals.first?.notice == .stepDone(.sleep))
        #expect(
            try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash")?.detailVersion
                == nil)
        _ = try await FullPull(database: store.database, source: source).run(epoch: store.epoch)
        #expect(try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").isEmpty)
        #expect(await source.calls.contains("detail"))
        #expect(result.retryAfter == nil)
        #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        #expect(
            try await SettingsRepository(database: store.database).settings().contains { $0.section == "syncFailure" })
        try await store.close()
    }
    @Test func malformedDetailCannotProveStepDisappeared() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check("old")))
        await source.configure(failMethod: "detail", methodFailure: .server(status: 200))
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

extension CheckOffReconcilerTests {
    @Test(arguments: [DataFailure.offline, .throttled(retryAfterSeconds: 60, status: 429), .server(status: 408)])
    func transientCheckOffFailuresKeepTheOptimisticMarkQueued(_ failure: DataFailure) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.checkOff(check()))
        await source.configure(failures: [failure])
        let result = try await OutboxFlusher(database: store.database, source: source).run(epoch: store.epoch)
        #expect(result.refusals.isEmpty)
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        #expect(
            try await TripRepository(database: store.database).checks(tripID: syncTrip, inputHash: "hash").first?.status
                == "done")
        try await store.close()
    }
}

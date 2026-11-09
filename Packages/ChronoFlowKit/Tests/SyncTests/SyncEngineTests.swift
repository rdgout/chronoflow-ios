import AppCore
import Foundation
import GRDB
import LocalStore
import Sync
import Testing

@Suite struct SyncEngineTests {
    @Test func concurrentRefreshesCoalesceOneRerun() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        await source.configure(hook: { method in if method == "identity" { await gate.block() } })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let first = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        for _ in 0..<20 { await engine.requestSync() }
        let second = Task { try await engine.refreshNow() }
        await source.configure()
        await gate.release()
        #expect(try await first.value.state == .idle)
        #expect(try await second.value.state == .idle)
        let count = await source.calls.filter { $0 == "identity" }.count
        #expect((2...3).contains(count))
        #expect(await source.maximumActiveCalls == 1)
        await engine.cancelAndWait()
        try await store.close()
    }
    @Test func queuedWriteDuringPullRunsAgainAndFlushes() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        await source.configure(hook: { method in if method == "trips" { await gate.block() } })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let run = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        _ = try await store.enqueue(.walkthrough)
        await engine.requestSync()
        await source.configure()
        await gate.release()
        #expect(try await run.value.pendingCount == 0)
        #expect(await source.calls.filter { $0 == "send" }.count == 1)
        await engine.cancelAndWait()
        try await store.close()
    }
    @Test(arguments: ["send", "identity", "account", "trips", "detail"])
    func invalidationRejectsEveryLateResponse(_ method: String) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        if method == "send" { _ = try await store.enqueue(.walkthrough) }
        await source.configure(hook: { call in if call == method { await gate.block() } })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let stream = await engine.events()
        let events = Task {
            var result: [SyncEvent] = []
            for await event in stream { result.append(event) }
            return result
        }
        let run = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        store.epoch.invalidate()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await source.calls.last == method)
        if method == "send" { #expect(try await OutboxRepository(database: store.database).pending().count == 1) }
        if method == "identity" {
            #expect(try await AccountRepository(database: store.database).account()?.name == "Local")
        }
        if method == "account" || method == "trips" {
            #expect(try await AccountRepository(database: store.database).account()?.syncedAt == nil)
        }
        if method == "detail" {
            #expect(try await TripRepository(database: store.database).plan(tripID: syncTrip, inputHash: "hash") == nil)
        }
        await engine.cancelAndWait()
        #expect(await events.value.count == 1)
        try await store.close()
    }
    @Test(arguments: ["send", "identity", "account", "trips", "detail"])
    func callerCancellationDrainsLateResponse(_ method: String) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        if method == "send" { _ = try await store.enqueue(.walkthrough) }
        await source.configure(hook: { call in if call == method { await gate.block() } })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let run = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        run.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await source.calls.last == method)
        await source.configure()
        #expect(try await engine.refreshNow().state == .idle)
        await engine.cancelAndWait()
        try await store.close()
    }
    @Test func cancelAndWaitStopsWorkAndPreservesQueue() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        _ = try await store.enqueue(.walkthrough)
        await source.configure(hook: { method in if method == "send" { await gate.block() } })
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let run = Task { try await engine.refreshNow() }
        await gate.waitUntilBlocked()
        let cancelled = Task { await engine.cancelAndWait() }
        run.cancel()
        await gate.release()
        await cancelled.value
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        await #expect(throws: CancellationError.self) { try await engine.refreshNow() }
        #expect(await source.calls == ["send"])
        try await store.close()
    }
    @Test func wrongAccountAndPreCancelledRequestNeverCallSource() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let wrong = SyncEngine(
            database: store.database, source: source,
            epoch: SyncEpoch(accountID: try AccountID(syncOther), generation: 1))
        await #expect(throws: StoreFailure.invalidAccountID) { try await wrong.refreshNow() }
        #expect(await source.calls.isEmpty)
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let gate = TestGate()
        let run = Task {
            await gate.block()
            return try await engine.refreshNow()
        }
        await gate.waitUntilBlocked()
        run.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await source.calls.isEmpty)
        await wrong.cancelAndWait()
        await engine.cancelAndWait()
        try await store.close()
    }
    @Test func firstPullThenOfflineRestartAndAccountIsolation() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        await source.configure(trips: [])
        try await store.database.write { db in
            try db.execute(sql: "DELETE FROM trips")
            try db.execute(sql: "DELETE FROM account")
        }
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        #expect(try await engine.refreshNow().state == .idle)
        let marker = try await AccountRepository(database: store.database).account()?.syncedAt
        #expect(marker != nil)
        await engine.cancelAndWait()
        try await store.database.close()
        try await store.database.open(accountID: syncAccount)
        let offline = SyncEngine(database: store.database, source: source, epoch: store.epoch, isOnline: { false })
        #expect(try await offline.refreshNow().state == .offline)
        #expect(try await AccountRepository(database: store.database).account()?.syncedAt == marker)
        let other = try await SyncStore(id: syncOther)
        #expect(try await AccountRepository(database: other.database).account()?.syncedAt == nil)
        #expect(try await OutboxRepository(database: other.database).pending().isEmpty)
        await offline.cancelAndWait()
        try await other.close()
        try await store.close()
    }
    @Test(arguments: [
        DataFailure.unauthorized(status: 401), .emailUnverified(status: 403), .offline, .server(status: 500),
    ])
    func sanitizedResultsRetainTransientWork(_ failure: DataFailure) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        _ = try await store.enqueue(.walkthrough)
        await source.configure(failures: [failure])
        let engine = SyncEngine(database: store.database, source: source, epoch: store.epoch)
        let result = try await engine.refreshNow()
        let state: SyncState
        switch failure {
        case .unauthorized: state = .unauthorized
        case .emailUnverified: state = .verificationRequired
        case .offline: state = .offline
        default: state = .idle
        }
        #expect(result.state == state)
        #expect(result.pendingCount == 1)
        if case .server = failure { #expect(result.retryAfter == 1) }
        await engine.cancelAndWait()
        try await store.close()
    }
    @Test func debounceWithInjectedSchedulerAndRefreshBypass() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let scheduler = ManualSyncScheduler()
        let engine = SyncEngine(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await scheduler.sleep($0) }))
        await engine.requestSync()
        await scheduler.waitForSleep()
        #expect(await source.calls.isEmpty)
        #expect(await scheduler.requestedDelays == [1])
        #expect(try await engine.refreshNow().state == .idle)
        await scheduler.advance()
        await engine.cancelAndWait()
        #expect(await source.calls.filter { $0 == "identity" }.count == 1)
        try await store.close()
    }
}

extension SyncEngineTests {
    @Test func cancelledEpochCannotEnterQueuedResponseTransaction() async throws {
        let store = try await SyncStore()
        let barrier = WriteBarrier()
        let beforeWrite = TestGate()
        let writer = Task { try await store.database.write { _ in barrier.block() } }
        await barrier.waitUntilBlocked()
        let response = Task {
            await beforeWrite.block()
            try await store.database.write(epoch: store.epoch) { db in
                try db.execute(sql: "UPDATE account SET name='late response'")
            }
        }
        await beforeWrite.waitUntilBlocked()
        await beforeWrite.release()
        store.epoch.invalidate()
        barrier.release()
        try await writer.value
        await #expect(throws: CancellationError.self) { try await response.value }
        #expect(try await AccountRepository(database: store.database).account()?.name == "Local")
        try await store.close()
    }
    @Test func cancelDrainsDebounceWithoutFiring() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let scheduler = ManualSyncScheduler()
        let engine = SyncEngine(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await scheduler.sleep($0) }))
        await engine.requestSync()
        await scheduler.waitForSleep()
        await engine.cancelAndWait()
        #expect(await scheduler.pendingCount == 0)
        #expect(await source.calls.isEmpty)
        try await store.close()
    }
}

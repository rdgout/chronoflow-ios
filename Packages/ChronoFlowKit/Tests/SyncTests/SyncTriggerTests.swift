import AppCore
import Foundation
import LocalStore
import Sync
import Testing

actor TriggerPath: SyncPathMonitoring {
    let stream: AsyncStream<Bool>
    let continuation: AsyncStream<Bool>.Continuation
    private(set) var stopped = false
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func updates() -> AsyncStream<Bool> { stream }
    func send(_ online: Bool) { continuation.yield(online) }
    func stop() {
        stopped = true
        continuation.finish()
    }
}

actor TriggerEvents {
    var unauthorized: [UInt64] = []
    var verification: [UInt64] = []
    func refused(_ epoch: UInt64) { unauthorized.append(epoch) }
    func verify(_ epoch: UInt64) { verification.append(epoch) }
}

@Suite struct SyncTriggerTests {
    @Test func openOutboxReconnectAndSceneBurstsDebounceAndStopDrains() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        let path = TriggerPath()
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }), path: path)
        try await lifecycle.start()
        await clock.waitForSleep()
        for _ in 0..<10 { await lifecycle.requestSync() }
        _ = try await store.enqueue(.walkthrough)
        await path.send(false)
        await path.send(true)
        #expect(await source.calls.isEmpty)
        _ = try await lifecycle.refreshNow()
        #expect(try await OutboxRepository(database: store.database).pending().isEmpty)
        await lifecycle.stop()
        #expect(await path.stopped)
        #expect(await clock.pendingCount == 0)
        await #expect(throws: CancellationError.self) { try await lifecycle.refreshNow() }
        try await store.close()
    }

    @Test func cappedBackoffResetAndServerDeadline() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        await source.configure(failMethod: "identity", methodFailure: .server(status: 500))
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }))
        try await lifecycle.start()
        await clock.waitForSleep()
        await clock.advance()
        var registrations = 2
        for delay in [1.0, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300] {
            while await clock.requestedDelays.count < registrations { await Task.yield() }
            #expect(await clock.requestedDelays.last == delay)
            if registrations == 12 { await source.configure() }
            await clock.advance()
            registrations += 1
        }
        // Wait for the successful recovery before starting a new failure series.
        while try await AccountRepository(database: store.database).account()?.syncedAt == nil { await Task.yield() }
        _ = try await lifecycle.refreshNow()
        await source.configure(failMethod: "identity", methodFailure: .server(status: 500))
        _ = try await lifecycle.refreshNow()
        while await clock.requestedDelays.last != 1 { await Task.yield() }
        #expect(await clock.requestedDelays.last == 1)
        await source.configure(failMethod: "identity", methodFailure: .throttled(retryAfterSeconds: 600, status: 429))
        await clock.advance()
        while await clock.requestedDelays.last != 600 { await Task.yield() }
        let before = await source.calls.count
        for _ in 0..<5 { await lifecycle.requestSync() }
        _ = try await lifecycle.refreshNow()
        #expect(await source.calls.count == before)
        await lifecycle.stop()
        #expect(await clock.pendingCount == 0)
        try await store.close()
    }

    @Test func coalescedRecoveryPreservesServerDeadline() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let gate = TestGate()
        let clock = ManualSyncScheduler()
        _ = try await store.enqueue(.walkthrough)
        await source.configure(
            failures: [.throttled(retryAfterSeconds: 900, status: 429)],
            hook: { method in if method == "identity" { await gate.block() } })
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }))
        try await lifecycle.start()
        await clock.waitForSleep()
        let run = Task { try await lifecycle.refreshNow() }
        await gate.waitUntilBlocked()
        await lifecycle.requestSync()
        await source.configure()
        await gate.release()
        let result = try await run.value
        #expect(result.pendingCount == 0)
        #expect(result.retryAfter == 900)
        while await clock.requestedDelays.last != 900 { await Task.yield() }
        let calls = await source.calls
        #expect(try await lifecycle.refreshNow() == result)
        #expect(await source.calls == calls)
        #expect(await clock.pendingCount == 1)
        await lifecycle.stop()
        #expect(await clock.pendingCount == 0)
        try await store.close()
    }

    @Test func offlineWaitsForHintAndVerificationProbesIdentityOnly() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let events = TriggerEvents()
        await source.configure(failMethod: "identity", methodFailure: .offline)
        let clock = ManualSyncScheduler()
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }),
            verification: { await events.verify($0) })
        try await lifecycle.start()
        #expect(try await lifecycle.refreshNow().state == .offline)
        await source.configure(failMethod: "account", methodFailure: .emailUnverified(status: 403))
        #expect(try await lifecycle.refreshNow().state == .verificationRequired)
        await source.configure(identity: identity(verified: false))
        _ = try await store.enqueue(.walkthrough)
        let before = await source.calls.count
        #expect(try await lifecycle.refreshNow().state == .verificationRequired)
        #expect(await Array(source.calls.dropFirst(before)) == ["identity"])
        #expect(try await OutboxRepository(database: store.database).pending().count == 1)
        await lifecycle.stop()
        try await store.close()
    }

    @Test func unauthorizedDispatchesOnceAndInvalidEpochCannotDispatch() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let events = TriggerEvents()
        await source.configure(failMethod: "identity", methodFailure: .unauthorized(status: 401))
        let clock = ManualSyncScheduler()
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }),
            unauthorized: { await events.refused($0) })
        try await lifecycle.start()
        #expect(try await lifecycle.refreshNow().state == .unauthorized)
        while await events.unauthorized.isEmpty { await Task.yield() }
        await lifecycle.requestSync()
        #expect(await events.unauthorized == [1])
        await lifecycle.stop()
        try await store.close()
    }
}

extension SyncTriggerTests {
    @Test func invalidatedUnauthorizedResponseCannotDispatchWipe() async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let events = TriggerEvents()
        let gate = TestGate()
        let clock = ManualSyncScheduler()
        await source.configure(
            failMethod: "identity", methodFailure: .unauthorized(status: 401),
            hook: { method in if method == "identity" { await gate.block() } })
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }),
            unauthorized: { await events.refused($0) })
        try await lifecycle.start()
        let refresh = Task { try await lifecycle.refreshNow() }
        await gate.waitUntilBlocked()
        store.epoch.invalidate()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await refresh.value }
        await lifecycle.stop()
        #expect(await events.unauthorized.isEmpty)
        try await store.close()
    }
}

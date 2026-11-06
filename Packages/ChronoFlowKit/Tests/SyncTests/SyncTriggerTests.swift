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

final class TriggerTime: @unchecked Sendable {
    private let lock = NSLock()
    private var value = syncDate
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: Double) { lock.withLock { value.addTimeInterval(seconds) } }
}

func triggerEventually(_ condition: @Sendable () async throws -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        await Task.yield()
    }
    return try await condition()
}

extension SyncTriggerTests {
    @Test func sessionPausePreservesServerDeadlineAndReplacementEpochDropsIt() async throws {
        let store = try await SyncStore()
        let accounts = SessionAccountDatabase(
            applicationSupport: store.root.appendingPathComponent("session"), namespace: .mock)
        try await accounts.open(accountID: AccountID(syncAccount))
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        let time = TriggerTime()
        await source.configure(failMethod: "identity", methodFailure: .throttled(retryAfterSeconds: 300, status: 429))
        let sync = SessionSync(
            accounts: accounts, scheduler: SyncScheduler(now: { time.now() }, sleep: { try await clock.sleep($0) }),
            source: { _ in source }, unauthorized: { _ in }, verification: { _ in })
        let session = StoredSession(token: "test", accountId: syncAccount)
        await sync.start(session: session, epoch: 5)
        #expect(try await sync.refreshNow()?.state == .failed)
        try #require(await triggerEventually { await clock.requestedDelays.last == 300 })
        await sync.setEnabled(false)
        #expect(await clock.pendingCount == 0)
        time.advance(10)
        let registrations = await clock.requestedDelays.count
        await sync.setEnabled(true)
        await sync.resume(session: session, epoch: 5)
        try #require(await triggerEventually { await clock.requestedDelays.count > registrations })
        #expect(await clock.requestedDelays.last == 290)
        #expect(await source.calls == ["identity"])
        #expect(try await sync.refreshNow()?.state == .failed)
        #expect(await source.calls == ["identity"])
        time.advance(290)
        await source.configure(trips: [])
        await clock.advance()
        try #require(await triggerEventually { await source.calls.count == 4 })
        #expect(await source.calls == ["identity", "identity", "account", "trips"])
        await sync.setEnabled(false)
        await sync.setEnabled(true)
        await sync.resume(session: session, epoch: 6)
        try #require(await triggerEventually { await clock.pendingCount == 1 })
        #expect(await clock.requestedDelays.last == 1)
        await sync.stop()
        try await accounts.close()
        try await store.close()
    }

    @Test func sessionPausePreservesFailureExponent() async throws {
        let store = try await SyncStore()
        let accounts = SessionAccountDatabase(
            applicationSupport: store.root.appendingPathComponent("session"), namespace: .mock)
        try await accounts.open(accountID: AccountID(syncAccount))
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        let time = TriggerTime()
        await source.configure(failMethod: "identity", methodFailure: .server(status: 500))
        let sync = SessionSync(
            accounts: accounts, scheduler: SyncScheduler(now: { time.now() }, sleep: { try await clock.sleep($0) }),
            source: { _ in source }, unauthorized: { _ in }, verification: { _ in })
        let session = StoredSession(token: "test", accountId: syncAccount)
        await sync.start(session: session, epoch: 5)
        _ = try await sync.refreshNow()
        try #require(await triggerEventually { await clock.requestedDelays.last == 1 })
        await sync.setEnabled(false)
        time.advance(2)
        await sync.setEnabled(true)
        await sync.resume(session: session, epoch: 5)
        _ = try await sync.refreshNow()
        try #require(await triggerEventually { await clock.requestedDelays.last == 2 })
        #expect(await source.calls == ["identity", "identity"])
        await sync.stop()
        try await accounts.close()
        try await store.close()
    }

    @Test func restartSeedsBackoffFromPersistedOutboxAttempts() async throws {
        let store = try await SyncStore()
        var row = try await store.enqueue(.walkthrough)
        row.attempts = 8
        try await OutboxRepository(database: store.database).upsert(row)
        let source = ScriptedSource()
        await source.configure(failMethod: "identity", methodFailure: .server(status: 500))
        let clock = ManualSyncScheduler()
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }))
        try await lifecycle.start()
        _ = try await lifecycle.refreshNow()
        try #require(await triggerEventually { await clock.requestedDelays.last == 256 })
        #expect(await clock.requestedDelays.last == 256)
        await lifecycle.stop()
        try await store.close()
    }
}

extension SyncTriggerTests {
    @Test(arguments: ["activation", "outbox", "reconnect"])
    func newTriggerPreemptsExponentialRetry(_ trigger: String) async throws {
        let store = try await SyncStore()
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        let path = TriggerPath()
        await source.configure(failMethod: "identity", methodFailure: .server(status: 500))
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { syncDate }, sleep: { try await clock.sleep($0) }), path: path)
        try await lifecycle.start()
        for delay in [1.0, 2, 4, 8, 16, 32, 64, 128] {
            _ = try await lifecycle.refreshNow()
            try #require(await triggerEventually { await clock.requestedDelays.last == delay })
        }
        let before = await source.calls.count
        let registrations = await clock.requestedDelays.count
        switch trigger {
        case "outbox": _ = try await store.enqueue(.walkthrough)
        case "reconnect":
            await path.send(false)
            await path.send(true)
        default: await lifecycle.requestSync()
        }
        try #require(await triggerEventually { await clock.requestedDelays.count > registrations })
        #expect(await clock.requestedDelays.last == 1)
        #expect(await source.calls.count == before)
        await clock.advance()
        let expected = trigger == "outbox" ? ["send", "identity"] : ["identity"]
        try #require(await triggerEventually { await source.calls.count >= before + expected.count })
        try #require(await triggerEventually { await clock.requestedDelays.last == 256 })
        #expect(await Array(source.calls.dropFirst(before)) == expected)
        await lifecycle.stop()
        try await store.close()
    }

    @Test func outboxBackoffCanBePreemptedButServerDeadlineCannot() async throws {
        let store = try await SyncStore()
        _ = try await store.enqueue(.walkthrough)
        let source = ScriptedSource()
        let clock = ManualSyncScheduler()
        let time = TriggerTime()
        await source.configure(trips: [], failures: [.throttled(retryAfterSeconds: 300, status: 429)])
        let lifecycle = SyncLifecycle(
            database: store.database, source: source, epoch: store.epoch,
            scheduler: SyncScheduler(now: { time.now() }, sleep: { try await clock.sleep($0) }))
        try await lifecycle.start()
        let result = try await lifecycle.refreshNow()
        #expect(result.serverRetryAfter == 300)
        try #require(await triggerEventually { await clock.requestedDelays.last == 300 })
        let before = await source.calls
        let registrations = await clock.requestedDelays.count
        await lifecycle.requestSync()
        _ = try await lifecycle.refreshNow()
        #expect(await source.calls == before)
        #expect(await clock.requestedDelays.count == registrations)
        await lifecycle.stop()
        try await store.close()
    }
}

import Foundation
import Testing

@testable import AppCore

private let wipeID = "019a562b-8000-7000-8000-000000000001"
private let replacementID = "019a562b-8000-7000-8000-000000000002"

private func wipeSession(_ id: String = wipeID) -> SessionResult {
    SessionResult(
        token: "captured-token",
        account: SessionAccount(
            id: id, name: "Test", email: "a@example.test",
            hasVerifiedEmail: true, policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"),
            walkthroughSeen: true))
}

private actor PendingChanges {
    var count = 2
    var flushes = 0
    func pending() -> Int { count }
    func flush() { flushes += 1 }
}

@Suite struct SignOutTests {
    @Test func offlinePendingReturnsConfirmationAndPreservesCredentials() async throws {
        let log = SessionEventLog()
        let pending = PendingChanges()
        let credentials = ControllerMemoryStore(log: log)
        let accounts = ControllerAccountStore(log: log)
        var hooks = SessionTeardown()
        hooks.pendingCount = { await pending.pending() }
        hooks.flush = {
            await pending.flush()
            throw DataFailure.offline
        }
        hooks.logout = { _ in await log.record("logout") }
        hooks.beginWipe = { _ in await log.record("marker") }
        let controller = SessionController(credentials: credentials, accounts: accounts, teardown: hooks)
        try await controller.accept(wipeSession())
        #expect(try await controller.signOut(discardPending: false) == .needsConfirmation(pendingCount: 2))
        #expect(await pending.flushes == 1)
        #expect(await credentials.data != nil)
        #expect(await controller.presence == .signedIn(accountID: wipeID))
        #expect(!(await log.events).contains("marker"))
        #expect(!(await log.events).contains("logout"))
    }

    @Test(arguments: [false, true]) func discardAndForcedOrderAndConcurrentRequests(_ forced: Bool) async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        let accounts = ControllerAccountStore(log: log)
        let gate = SessionTestGate()
        var hooks = SessionTeardown()
        hooks.flush = { await log.record("flush") }
        hooks.beginWipe = { _ in
            await log.record("marker")
            await gate.wait()
        }
        hooks.logout = { old in
            #expect(old.token == "captured-token")
            await log.record("logout")
        }
        hooks.detach = { await log.record("detach") }
        hooks.erase = { _ in await log.record("erase") }
        hooks.finishWipe = { await log.record("finish") }
        // Block the deadline until canceled; no real clock or sleep.
        hooks.sleep = { _ in
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                c.resume(throwing: CancellationError())
            }
        }
        let controller = SessionController(
            credentials: credentials, accounts: accounts, teardown: hooks,
            stopSync: { await log.record("drain") })
        try await controller.accept(wipeSession())
        let first = Task { try await controller.signOut(discardPending: true, unauthorized: forced) }
        await gate.waitUntilEntered()
        let second = Task { try await controller.signOut(discardPending: true, unauthorized: forced) }
        await gate.release()
        #expect(try await first.value == .signedOut)
        #expect(try await second.value == .signedOut)
        let events = await log.events
        #expect(events.filter { $0 == "marker" }.count == 1)
        #expect(!events.contains("flush"))
        #expect(events.contains("logout") == !forced)
        let marker = try #require(events.firstIndex(of: "marker"))
        let drain = try #require(events.dropFirst(marker).firstIndex(of: "drain"))
        let detach = try #require(events.firstIndex(of: "detach"))
        let close = try #require(events.dropFirst(detach).firstIndex(of: "close"))
        let erase = try #require(events.firstIndex(of: "erase"))
        let delete = try #require(events.firstIndex(of: "delete"))
        #expect(marker < drain && drain < detach && detach < close && close < erase && erase < delete)
        #expect(await credentials.data == nil)
        #expect(await controller.presence == .signedOut)
    }

    @Test func oldUnauthorizedCannotWipeReplacementAndCurrentUnauthorizedWipesOnce() async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        var hooks = SessionTeardown()
        hooks.beginWipe = { _ in await log.record("marker") }
        hooks.logout = { _ in await log.record("logout") }
        let controller = SessionController(
            credentials: credentials, accounts: ControllerAccountStore(log: log), teardown: hooks)
        try await controller.accept(wipeSession())
        let oldEpoch = await controller.epoch
        try await controller.accept(wipeSession(replacementID))
        _ = try await controller.unauthorized(epoch: oldEpoch)
        #expect(await controller.storedSession?.accountId == replacementID)
        #expect(!(await log.events).contains("marker"))
        let current = await controller.epoch
        _ = try await controller.unauthorized(epoch: current)
        _ = try await controller.unauthorized(epoch: current)
        #expect((await log.events).filter { $0 == "marker" }.count == 1)
        #expect(!(await log.events).contains("logout"))
        #expect(await credentials.data == nil)
    }

    @Test func failedWipeRetriesBeforeAnotherAccountCanOpen() async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        let pending = PendingChanges()
        var hooks = SessionTeardown()
        hooks.prepare = {
            if await pending.pending() == 3 { throw SessionTestFailure.unavailable }
        }
        hooks.beginWipe = { _ in await pending.setCount(3) }
        hooks.erase = { _ in throw SessionTestFailure.unavailable }
        let controller = SessionController(
            credentials: credentials, accounts: ControllerAccountStore(log: log), teardown: hooks)
        try await controller.accept(wipeSession())
        await #expect(throws: SessionTestFailure.unavailable) {
            try await controller.signOut(discardPending: true, unauthorized: true)
        }
        #expect(await credentials.data == nil)
        await #expect(throws: SessionTestFailure.unavailable) {
            try await controller.accept(wipeSession(replacementID))
        }
        #expect(!(await log.events).contains("open:" + replacementID))
    }
}

extension PendingChanges { func setCount(_ count: Int) { self.count = count } }

private actor CancelableLogout {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var entered: [CheckedContinuation<Void, Never>] = []
    private(set) var canceled = false
    func wait() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                for waiter in entered { waiter.resume() }
                entered.removeAll()
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }
    func waitUntilEntered() async {
        if continuation != nil { return }
        await withCheckedContinuation { entered.append($0) }
    }
    private func cancel() {
        canceled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

extension SignOutTests {
    @Test func logoutDeadlineCancelsRequestAndStillErases() async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        let request = CancelableLogout()
        let deadline = SessionTestGate()
        var hooks = SessionTeardown()
        hooks.logout = { _ in try await request.wait() }
        hooks.sleep = { seconds in
            #expect(seconds == 3)
            await deadline.wait()
        }
        hooks.erase = { _ in await log.record("erase") }
        let controller = SessionController(
            credentials: credentials, accounts: ControllerAccountStore(log: log), teardown: hooks)
        try await controller.accept(wipeSession())
        let task = Task { try await controller.signOut(discardPending: true) }
        await request.waitUntilEntered()
        await deadline.waitUntilEntered()
        await deadline.release()
        #expect(try await task.value == .signedOut)
        #expect(await request.canceled)
        #expect((await log.events).contains("erase"))
        #expect(await credentials.data == nil)
    }
}

extension SignOutTests {
    @Test func activationCannotCaptureCredentialsDuringReplacement() async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        let controller = SessionController(credentials: credentials, accounts: ControllerAccountStore(log: log))
        try await controller.accept(wipeSession())
        let old = try #require(await controller.activeSession())
        let write = SessionTestGate()
        await credentials.configure(writeGate: write)
        let replacement = Task {
            try await controller.accept(SessionResult(token: "replacement-token", account: wipeSession().account))
        }
        await write.waitUntilEntered()
        #expect(await controller.activeSession() == nil)
        await write.release()
        try await replacement.value
        let current = try #require(await controller.activeSession())
        #expect(current.epoch > old.epoch)
        #expect(current.session.token == "replacement-token")
        _ = try await controller.unauthorized(epoch: old.epoch)
        #expect(await controller.activeSession() == current)
    }
}

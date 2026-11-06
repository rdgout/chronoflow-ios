import Foundation
import Testing

@testable import AppCore

func sessionTestIsMainThread() -> Bool { Thread.isMainThread }

private let sessionAccountA = "019a562b-8000-7000-8000-000000000001"
private let sessionAccountB = "019a562b-8000-7000-8000-000000000002"

enum SessionTestFailure: Error { case unavailable }

actor SessionEventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

actor SessionTestGate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        entered = true
        for waiter in entryWaiters { waiter.resume() }
        entryWaiters.removeAll()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }

    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

actor ControllerMemoryStore: SessionStore {
    var data: Data?
    var readFails = false
    var writeFails = false
    var deleteFails = false
    var deletes = 0
    let log: SessionEventLog
    let writeGate: SessionTestGate?
    init(_ data: Data? = nil, log: SessionEventLog, writeGate: SessionTestGate? = nil) {
        self.data = data
        self.log = log
        self.writeGate = writeGate
    }
    func configure(readFails: Bool = false, writeFails: Bool = false, deleteFails: Bool = false) {
        self.readFails = readFails
        self.writeFails = writeFails
        self.deleteFails = deleteFails
    }
    func read() async throws -> Data? {
        #expect(!sessionTestIsMainThread())
        await log.record("read")
        if readFails { throw SessionTestFailure.unavailable }
        return data
    }
    func write(_ data: Data) async throws {
        #expect(!sessionTestIsMainThread())
        await log.record("write")
        await writeGate?.wait()
        if writeFails { throw SessionTestFailure.unavailable }
        self.data = data
    }
    func delete() async throws {
        if deleteFails { throw SessionTestFailure.unavailable }
        await log.record("delete")
        data = nil
        deletes += 1
    }
}

actor ControllerAccountStore: SessionAccountStore {
    let log: SessionEventLog
    let gate: SessionTestGate?
    private var openFails = false
    private var upsertFails = false
    private(set) var accountID: AccountID?
    init(log: SessionEventLog, gate: SessionTestGate? = nil) {
        self.log = log
        self.gate = gate
    }
    func configure(openFails: Bool = false, upsertFails: Bool = false) {
        self.openFails = openFails
        self.upsertFails = upsertFails
    }
    func open(accountID: AccountID) async throws {
        #expect(!sessionTestIsMainThread())
        await log.record("open:" + accountID.rawValue)
        await gate?.wait()
        if openFails { throw SessionTestFailure.unavailable }
        self.accountID = accountID
    }
    func upsert(_ account: SessionAccount) async throws {
        await log.record("upsert:" + account.id)
        if upsertFails { throw SessionTestFailure.unavailable }
    }
    func close() async {
        accountID = nil
        await log.record("close")
    }
}

private func sessionResult(_ id: String = sessionAccountA) -> SessionResult {
    SessionResult(
        token: "test-token",
        account: SessionAccount(
            id: id, name: "Name", email: "email@example.test",
            hasVerifiedEmail: true, policies: AccountPolicies(termsVersion: "1", privacyVersion: "1"),
            walkthroughSeen: false))
}

struct SessionControllerTests {
    @Test func acceptOrdersDatabaseCredentialsPublicationAndSyncWithoutFakingMarker() async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        let accounts = ControllerAccountStore(log: log)
        let controller = SessionController(credentials: credentials, accounts: accounts) { _ in await log.record("sync")
        }
        #expect(await controller.presence == nil)
        let updates = await controller.updates()
        var iterator = updates.makeAsyncIterator()
        try await controller.accept(sessionResult())
        #expect(await iterator.next() == SessionUpdate(presence: .signedIn(accountID: sessionAccountA), epoch: 1))
        #expect(await log.events == ["open:" + sessionAccountA, "upsert:" + sessionAccountA, "write", "sync"])
        let restored = try #require(await credentials.data)
        #expect(StoredSession.parse(restored) == StoredSession(token: "test-token", accountId: sessionAccountA))
        #expect(await controller.epoch == 1)
        #expect(await controller.storedSession?.accountId == sessionAccountA)
    }

    @Test(arguments: ["open", "upsert", "keychain"])
    func failuresCannotPublishASessionOrSync(_ stage: String) async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(log: log)
        await credentials.configure(writeFails: stage == "keychain")
        let accounts = ControllerAccountStore(log: log)
        await accounts.configure(openFails: stage == "open", upsertFails: stage == "upsert")
        let controller = SessionController(credentials: credentials, accounts: accounts) { _ in await log.record("sync")
        }
        await #expect(throws: stage == "keychain" ? SessionFailure.credentialWrite : SessionFailure.databaseUnavailable)
        {
            try await controller.accept(sessionResult())
        }
        #expect(await controller.presence == nil)
        #expect(await controller.storedSession == nil)
        #expect(await credentials.data == nil)
        #expect(!(await log.events).contains("sync"))
        if stage != "keychain" { #expect(!(await log.events).contains("write")) }
    }

    @Test func restoreRetriesUnavailableCredentialsWithoutDeletionAndOpensTheMatchingDatabase() async throws {
        let log = SessionEventLog()
        let data = try JSONEncoder().encode(StoredSession(token: "legacy", accountId: sessionAccountA.uppercased()))
        let credentials = ControllerMemoryStore(data, log: log)
        await credentials.configure(readFails: true)
        let accounts = ControllerAccountStore(log: log)
        let controller = SessionController(credentials: credentials, accounts: accounts)
        await #expect(throws: SessionFailure.credentialsUnavailable) { try await controller.restore() }
        #expect(await credentials.deletes == 0)
        #expect(await credentials.data == data)
        #expect(await controller.presence == nil)
        await credentials.configure()
        await accounts.configure(openFails: true)
        await #expect(throws: SessionFailure.databaseUnavailable) { try await controller.restore() }
        #expect(await credentials.data == data)
        await accounts.configure()
        #expect(try await controller.restore() == .signedIn(accountID: sessionAccountA))
        #expect(await accounts.accountID?.rawValue == sessionAccountA)
        #expect(await controller.storedSession?.accountId == sessionAccountA)
    }

    @Test(arguments: [nil, Data("invalid".utf8), Data(#"{"token":"x","accountId":"../outside"}"#.utf8)])
    func absentAndMalformedCredentialsSignOut(_ data: Data?) async throws {
        let log = SessionEventLog()
        let credentials = ControllerMemoryStore(data, log: log)
        let controller = SessionController(credentials: credentials, accounts: ControllerAccountStore(log: log))
        #expect(try await controller.restore() == .signedOut)
        #expect(await credentials.data == nil)
        #expect(await credentials.deletes == (data == nil ? 0 : 1))
        #expect(!(await log.events).contains(where: { $0.hasPrefix("open:") }))
    }

    @Test func malformedCredentialsAreRetainedWhenDeletionIsTemporarilyUnavailable() async throws {
        let log = SessionEventLog()
        let invalid = Data("malformed".utf8)
        let credentials = ControllerMemoryStore(invalid, log: log)
        await credentials.configure(deleteFails: true)
        let controller = SessionController(credentials: credentials, accounts: ControllerAccountStore(log: log))
        await #expect(throws: SessionFailure.credentialsUnavailable) { try await controller.restore() }
        #expect(await credentials.data == invalid)
        #expect(await controller.presence == nil)
        await credentials.configure()
        #expect(try await controller.restore() == .signedOut)
        #expect(await credentials.data == nil)
    }

    @Test func invalidSessionResultDoesNotTouchStorage() async throws {
        let log = SessionEventLog()
        let controller = SessionController(
            credentials: ControllerMemoryStore(log: log), accounts: ControllerAccountStore(log: log))
        await #expect(throws: SessionFailure.invalidResult) { try await controller.accept(sessionResult("../path")) }
        let emptyToken = SessionResult(token: "  ", account: sessionResult().account)
        await #expect(throws: SessionFailure.invalidResult) { try await controller.accept(emptyToken) }
        #expect(await log.events.isEmpty)
        #expect(await controller.presence == nil)
    }

    @Test func newestConcurrentAcceptWinsAndStaleCompletionCannotWriteCredentials() async throws {
        let log = SessionEventLog()
        let gate = SessionTestGate()
        let credentials = ControllerMemoryStore(log: log)
        let accounts = ControllerAccountStore(log: log, gate: gate)
        let controller = SessionController(credentials: credentials, accounts: accounts)
        let first = Task { try await controller.accept(sessionResult()) }
        await gate.waitUntilEntered()
        let second = Task { try await controller.accept(sessionResult(sessionAccountB)) }
        while await controller.generation < 2 { await Task.yield() }
        await gate.release()
        await #expect(throws: SessionFailure.superseded) { try await first.value }
        try await second.value
        #expect(await controller.presence == .signedIn(accountID: sessionAccountB))
        #expect(StoredSession.parse(try #require(await credentials.data))?.accountId == sessionAccountB)
        #expect((await log.events).filter { $0 == "write" }.count == 1)
    }

    @Test func cancelingAnAcceptBeforeOpenCompletesPreventsPublication() async throws {
        let log = SessionEventLog()
        let gate = SessionTestGate()
        let credentials = ControllerMemoryStore(log: log)
        let controller = SessionController(
            credentials: credentials, accounts: ControllerAccountStore(log: log, gate: gate))
        let task = Task { try await controller.accept(sessionResult()) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await controller.presence == nil)
        #expect(await credentials.data == nil)
    }

    @Test func committedWritePublishesBeforeANewerInvalidAccept() async throws {
        let log = SessionEventLog()
        let gate = SessionTestGate()
        let credentials = ControllerMemoryStore(log: log, writeGate: gate)
        let accounts = ControllerAccountStore(log: log)
        let controller = SessionController(credentials: credentials, accounts: accounts)
        var updates = await controller.updates().makeAsyncIterator()
        let first = Task { try await controller.accept(sessionResult()) }
        await gate.waitUntilEntered()
        let second = Task { try await controller.accept(sessionResult("invalid")) }
        while await controller.generation < 2 { await Task.yield() }
        await gate.release()
        let firstResult = await first.result
        await #expect(throws: SessionFailure.invalidResult) { try await second.value }
        #expect(await controller.presence == .signedIn(accountID: sessionAccountA))
        #expect(await controller.storedSession == StoredSession.parse(try #require(await credentials.data)))
        #expect(await controller.epoch == 1)
        try firstResult.get()
        #expect(await updates.next() == SessionUpdate(presence: .signedIn(accountID: sessionAccountA), epoch: 1))
    }

    @Test func cancellationDuringSuccessfulWriteStillCommitsAndPublishes() async throws {
        let log = SessionEventLog()
        let gate = SessionTestGate()
        let credentials = ControllerMemoryStore(log: log, writeGate: gate)
        let controller = SessionController(credentials: credentials, accounts: ControllerAccountStore(log: log))
        var updates = await controller.updates().makeAsyncIterator()
        let task = Task { try await controller.accept(sessionResult()) }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()
        let result = await task.result
        #expect(await controller.presence == .signedIn(accountID: sessionAccountA))
        #expect(await controller.storedSession == StoredSession.parse(try #require(await credentials.data)))
        try result.get()
        #expect(await updates.next() == SessionUpdate(presence: .signedIn(accountID: sessionAccountA), epoch: 1))
    }

    @Test func supersedingDuringSyncDoesNotRejectAnAlreadyCommittedAccept() async throws {
        let log = SessionEventLog()
        let gate = SessionTestGate()
        let controller = SessionController(
            credentials: ControllerMemoryStore(log: log), accounts: ControllerAccountStore(log: log)
        ) { _ in await gate.wait() }
        let first = Task { try await controller.accept(sessionResult()) }
        await gate.waitUntilEntered()
        #expect(await controller.presence == .signedIn(accountID: sessionAccountA))
        let second = Task { try await controller.accept(sessionResult("invalid")) }
        while await controller.generation < 2 { await Task.yield() }
        await gate.release()
        let firstResult = await first.result
        await #expect(throws: SessionFailure.invalidResult) { try await second.value }
        try firstResult.get()
    }
}

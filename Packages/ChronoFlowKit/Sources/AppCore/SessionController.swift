import Foundation

public struct AccountPolicies: Codable, Sendable, Equatable {
    public let termsVersion: String
    public let privacyVersion: String
    public let acceptedTermsVersion: String?
    public let acceptedTermsAt: String?

    public init(
        termsVersion: String, privacyVersion: String, acceptedTermsVersion: String? = nil,
        acceptedTermsAt: String? = nil
    ) {
        self.termsVersion = termsVersion
        self.privacyVersion = privacyVersion
        self.acceptedTermsVersion = acceptedTermsVersion
        self.acceptedTermsAt = acceptedTermsAt
    }
}

public struct SessionAccount: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let hasVerifiedEmail: Bool
    public let policies: AccountPolicies
    public let walkthroughSeen: Bool

    public init(
        id: String, name: String, email: String, hasVerifiedEmail: Bool, policies: AccountPolicies,
        walkthroughSeen: Bool
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.hasVerifiedEmail = hasVerifiedEmail
        self.policies = policies
        self.walkthroughSeen = walkthroughSeen
    }
}

public struct SessionResult: Codable, Sendable, Equatable {
    public let token: String
    public let account: SessionAccount
    public let tripId: String?

    enum CodingKeys: String, CodingKey { case kind, token, account, tripId }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .kind) == "session" else { throw DataFailure.server(status: nil) }
        token = try c.decode(String.self, forKey: .token)
        account = try c.decode(SessionAccount.self, forKey: .account)
        tripId = try c.decodeIfPresent(String.self, forKey: .tripId)
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (try? AccountID(account.id)) != nil
        else { throw DataFailure.server(status: nil) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("session", forKey: .kind)
        try c.encode(token, forKey: .token)
        try c.encode(account, forKey: .account)
        try c.encode(tripId, forKey: .tripId)
    }

    public init(token: String, account: SessionAccount, tripId: String? = nil) {
        self.token = token
        self.account = account
        self.tripId = tripId
    }
}

public enum SessionFailure: Error, Sendable, Equatable {
    case credentialsUnavailable, databaseUnavailable, credentialWrite, invalidResult, superseded
}

public protocol SessionAccountStore: Sendable {
    func open(accountID: AccountID) async throws
    func upsert(_ account: SessionAccount) async throws
    func close() async throws
    func markEmailVerified(accountID: AccountID, email: String) async throws -> Bool
}

extension SessionAccountStore {
    public func markEmailVerified(accountID: AccountID, email: String) async throws -> Bool {
        throw SessionFailure.databaseUnavailable
    }
}

public protocol SessionControlling: Sendable {
    func restore() async throws -> SessionPresence
    func accept(_ result: SessionResult) async throws
    func signOut(discardPending: Bool, unauthorized: Bool) async throws -> SignOutResult
}

public struct SessionSnapshot: Sendable, Equatable {
    public let session: StoredSession
    public let epoch: UInt64
}

public struct SessionUpdate: Sendable, Equatable {
    public let presence: SessionPresence
    public let epoch: UInt64
}

public actor SessionController: SessionControlling {
    private let credentials: any SessionStore
    private let accounts: any SessionAccountStore
    private var transitioning = false
    private let teardown: SessionTeardown
    private(set) var signOutFlight: Task<SignOutResult, any Error>?
    private var unconditionalSignOut: (discardPending: Bool, unauthorized: Bool)?
    private var discardRequested = false
    private var unauthorizedRequested = false
    public private(set) var pendingUnauthorizedEpoch: UInt64?
    private let stopSync: @Sendable () async -> Void
    private let requestSync: @Sendable (UInt64) async -> Void
    private var tail: Task<Void, Never>?
    private(set) var generation: UInt64 = 0
    private var observers: [UUID: AsyncStream<SessionUpdate>.Continuation] = [:]
    public private(set) var presence: SessionPresence?
    public private(set) var epoch: UInt64 = 0
    public private(set) var storedSession: StoredSession?

    public init(
        credentials: any SessionStore, accounts: any SessionAccountStore,
        teardown: SessionTeardown = SessionTeardown(),
        stopSync: @escaping @Sendable () async -> Void = {},
        requestSync: @escaping @Sendable (UInt64) async -> Void = { _ in }
    ) {
        self.credentials = credentials
        self.accounts = accounts
        self.requestSync = requestSync
        self.stopSync = stopSync
        self.teardown = teardown
    }

    public func activeSession() -> SessionSnapshot? {
        guard !transitioning, let storedSession, presence == .signedIn(accountID: storedSession.accountId) else {
            return nil
        }
        return SessionSnapshot(session: storedSession, epoch: epoch)
    }

    public func updates() -> AsyncStream<SessionUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SessionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        if let presence { continuation.yield(SessionUpdate(presence: presence, epoch: epoch)) }
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    public func restore() async throws -> SessionPresence {
        generation &+= 1
        let generation = generation
        let previous = tail
        let task = Task { [weak self] () throws -> SessionPresence in
            await previous?.value
            guard let self else { throw CancellationError() }
            return try await self.performRestore(generation: generation)
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func accept(_ result: SessionResult) async throws {
        generation &+= 1
        let generation = generation
        let previous = tail
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { throw CancellationError() }
            try await self.performAccept(result, generation: generation)
        }
        tail = Task { _ = await task.result }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func confirmEmailVerification(expected: SessionSnapshot, email: String) async throws -> Bool {
        let generation = generation
        let previous = tail
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return false }
            return try await self.performVerification(expected: expected, email: email, generation: generation)
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performVerification(expected: SessionSnapshot, email: String, generation: UInt64) async throws -> Bool
    {
        try Task.checkCancellation()
        guard self.generation == generation, activeSession() == expected else { return false }
        let updated = try await accounts.markEmailVerified(
            accountID: AccountID(expected.session.accountId), email: email)
        try Task.checkCancellation()
        guard updated, self.generation == generation, activeSession() == expected else { return false }
        await requestSync(expected.epoch)
        return self.generation == generation && activeSession() == expected
    }

    public func signOut(discardPending: Bool, unauthorized: Bool = false) async throws -> SignOutResult {
        try await enqueueSignOut(discardPending: discardPending, unauthorized: unauthorized, expectedEpoch: nil)
    }

    public func signOut(expected: SessionSnapshot, discardPending: Bool) async throws -> SignOutResult {
        guard activeSession() == expected else { return .signedOut }
        return try await enqueueSignOut(
            discardPending: discardPending, unauthorized: false, expectedEpoch: expected.epoch)
    }

    public func unauthorized(epoch: UInt64) async throws -> SignOutResult {
        guard self.epoch == epoch else { return .signedOut }
        pendingUnauthorizedEpoch = epoch
        let result = try await enqueueSignOut(discardPending: true, unauthorized: true, expectedEpoch: epoch)
        if pendingUnauthorizedEpoch == epoch { pendingUnauthorizedEpoch = nil }
        return result
    }

    public func retryUnauthorized() async throws {
        guard let epoch = pendingUnauthorizedEpoch else { return }
        if self.epoch != epoch {
            pendingUnauthorizedEpoch = nil
            return
        }
        _ = try await unauthorized(epoch: epoch)
    }

    private func enqueueSignOut(
        discardPending: Bool, unauthorized: Bool, expectedEpoch: UInt64?
    ) async throws -> SignOutResult {
        if let expectedEpoch, self.epoch != expectedEpoch { return .signedOut }
        discardRequested = discardRequested || discardPending
        unauthorizedRequested = unauthorizedRequested || unauthorized
        if expectedEpoch == nil {
            generation &+= 1
            unconditionalSignOut = (
                (unconditionalSignOut?.discardPending ?? false) || discardPending,
                (unconditionalSignOut?.unauthorized ?? false) || unauthorized
            )
        }
        if let signOutFlight { return try await signOutFlight.value }
        let previous = tail
        let task = Task { [weak self] () throws -> SignOutResult in
            await previous?.value
            guard let self else { throw CancellationError() }
            return try await self.performSignOut(expectedEpoch: expectedEpoch)
        }
        signOutFlight = task
        tail = Task { _ = await task.result }
        // Once requested, cleanup must complete even if its UI caller disappears.
        return try await task.value
    }

    private func performSignOut(expectedEpoch: UInt64?) async throws -> SignOutResult {
        defer {
            signOutFlight = nil
            unconditionalSignOut = nil
            discardRequested = false
            unauthorizedRequested = false
        }
        if let expectedEpoch, epoch != expectedEpoch {
            guard let unconditionalSignOut else { return .signedOut }
            discardRequested = unconditionalSignOut.discardPending
            unauthorizedRequested = unconditionalSignOut.unauthorized
        }
        var captured = storedSession
        if captured == nil {
            await stopSync()
            try await accounts.close()
            try await teardown.prepare()
            captured = try await credentials.readStoredSession()
        }
        guard let session = captured else {
            try await credentials.delete()
            publish(.signedOut)
            await teardown.detach()
            return .signedOut
        }
        if !unauthorizedRequested, !discardRequested {
            var count = try await teardown.pendingCount()
            if count > 0 {
                try? await teardown.flush()
                count = try await teardown.pendingCount()
            }
            if count > 0, !discardRequested, !unauthorizedRequested {
                return .needsConfirmation(pendingCount: count)
            }
        }
        let id = try AccountID(session.accountId)
        try await teardown.beginWipe(id)
        // Publication invalidates session consumers before awaiting any old work.
        storedSession = nil
        publish(.signedOut)
        await stopSync()
        if !unauthorizedRequested { await bestEffortLogout(session) }
        await teardown.detach()
        try await accounts.close()
        var failure: (any Error)?
        do { try await teardown.erase(id) } catch { failure = error }
        do { try await credentials.delete() } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
        try await teardown.finishWipe()
        return .signedOut
    }

    private func bestEffortLogout(_ session: StoredSession) async {
        let teardown = teardown
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await teardown.logout(session) }
            group.addTask { try? await teardown.sleep(3) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func check(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard self.generation == generation else { throw SessionFailure.superseded }
    }

    private func performRestore(generation: UInt64) async throws -> SessionPresence {
        try check(generation)
        transitioning = true
        defer { transitioning = false }
        await stopSync()
        try await teardown.prepare()
        try check(generation)
        let session: StoredSession?
        do { session = try await credentials.readStoredSession() } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SessionFailure.credentialsUnavailable
        }
        try check(generation)
        guard let session else {
            do { try await accounts.close() } catch is CancellationError { throw CancellationError() } catch {
                throw SessionFailure.databaseUnavailable
            }
            try check(generation)
            storedSession = nil
            publish(.signedOut)
            return .signedOut
        }
        guard let id = try? AccountID(session.accountId) else {
            do { try await credentials.delete() } catch is CancellationError { throw CancellationError() } catch {
                throw SessionFailure.credentialsUnavailable
            }
            try check(generation)
            do { try await accounts.close() } catch is CancellationError { throw CancellationError() } catch {
                throw SessionFailure.databaseUnavailable
            }
            try check(generation)
            storedSession = nil
            publish(.signedOut)
            return .signedOut
        }
        do { try await accounts.open(accountID: id) } catch is CancellationError { throw CancellationError() } catch {
            throw SessionFailure.databaseUnavailable
        }
        try check(generation)
        storedSession = StoredSession(token: session.token, accountId: id.rawValue)
        publish(.signedIn(accountID: id.rawValue))
        transitioning = false
        await requestSync(epoch)
        try check(generation)
        return .signedIn(accountID: id.rawValue)
    }

    private func performAccept(_ result: SessionResult, generation: UInt64) async throws {
        try check(generation)
        guard let id = try? AccountID(result.account.id),
            !result.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SessionFailure.invalidResult
        }
        transitioning = true
        defer { transitioning = false }
        await stopSync()
        try await teardown.prepare()
        try check(generation)
        if case .signedIn(let accountID) = presence, accountID != id.rawValue {
            storedSession = nil
            publish(.signedOut)
        }
        do {
            try await accounts.open(accountID: id)
            try check(generation)
            try await accounts.upsert(result.account)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SessionFailure { throw error } catch { throw SessionFailure.databaseUnavailable }
        try check(generation)
        let session = StoredSession(token: result.token, accountId: id.rawValue)
        do { try await credentials.write(JSONEncoder().encode(session)) } catch is CancellationError {
            throw CancellationError()
        } catch { throw SessionFailure.credentialWrite }
        // A successful credential write commits the session, even if superseded or canceled during the write.
        storedSession = session
        publish(.signedIn(accountID: id.rawValue))
        transitioning = false
        await requestSync(epoch)
    }

    private func publish(_ value: SessionPresence) {
        epoch &+= 1
        presence = value
        for observer in observers.values { observer.yield(SessionUpdate(presence: value, epoch: epoch)) }
    }

    deinit {
        tail?.cancel()
        for observer in observers.values { observer.finish() }
    }
}

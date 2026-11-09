import AppCore
import Auth
import DataAccess
import Foundation
import Testing

actor AuthTestSession: SessionControlling {
    private(set) var accepted: [SessionResult] = []
    var failure: SessionFailure?
    func restore() -> SessionPresence { .signedOut }
    func signOut(discardPending: Bool, unauthorized: Bool) -> SignOutResult { .signedOut }
    func accept(_ result: SessionResult) throws {
        if let failure { throw failure }
        accepted.append(result)
    }
    func fail(_ failure: SessionFailure?) { self.failure = failure }
}

func authTestSource(verified: Bool = true, twoFactor: Bool = false) throws -> MockDataSource {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    var snapshot = try JSONDecoder().decode(
        AccountSnapshot.self,
        from: Data(contentsOf: root.appending(path: "DataAccessTests/Fixtures/account/snapshot.json")))
    snapshot.hasVerifiedEmail = verified
    snapshot.settings.policies = AccountPolicies(
        termsVersion: "1.0", privacyVersion: "1.0", acceptedTermsVersion: "1.0")
    let account = MockServerAccount(
        snapshot: snapshot, password: "Password123!", twoFactorCode: twoFactor ? "123456" : nil, walkthroughSeen: true)
    let id = snapshot.id
    return MockDataSource(
        seed: MockServerState(accounts: [account]), delay: { 0 }, sleep: { _ in },
        assertionProvider: { credential, _ in credential.id == "AQ" ? id : nil })
}

@MainActor struct SignInModelTests {
    @Test(arguments: [true, false]) func verifiedAndUnverifiedAcceptOnceAndClearSecrets(_ verified: Bool) async throws {
        let session = AuthTestSession()
        var routes: [Route] = []
        let model = SignInModel(
            source: try authTestSource(verified: verified), session: session,
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test", route: { routes.append($0) }
        )
        #expect(model.email.isEmpty && model.password.isEmpty)
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        await model.submitPassword()
        #expect(await session.accepted.count == 1)
        #expect(routes == [verified ? .today : .verify])
        #expect(model.password.isEmpty && model.email == "demo@example.com" && !model.form.busy)
    }
    @Test func twoFactorNeverAcceptsSessionAndBackDiscardsChallenge() async throws {
        let session = AuthTestSession()
        let model = SignInModel(
            source: try authTestSource(twoFactor: true), session: session,
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test",
            route: { _ in Issue.record("Early route") })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        await model.submitPassword()
        #expect(model.navigation.path == [.twoFactor] && model.navigation.challengeID != nil)
        #expect(await session.accepted.isEmpty)
        #expect(model.password.isEmpty)
        model.navigation.discardChallenge()
        #expect(model.navigation.challengeID == nil)
    }
    @Test func blankCredentialsThrottleServerAndOfflinePreserveEmailAndClearPassword() async throws {
        let source = try authTestSource()
        let model = SignInModel(
            source: source, session: AuthTestSession(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", route: { _ in })
        await model.submitPassword()
        #expect(model.form.fields["email"]?.key == "Please fill this in.")
        model.editEmail("retained@example.com")
        model.editPassword("wrong")
        await model.submitPassword()
        #expect(model.form.banner == .credentials && model.form.fields.isEmpty && model.password.isEmpty)
        for failure in [DataFailure.server(status: 500), .throttled(retryAfterSeconds: 40, status: 429), .offline] {
            await source.failNext(method: .signIn, error: failure)
            model.editPassword("another attempt")
            #expect(model.form.banner == nil)
            await model.submitPassword()
            #expect(model.form.failure == failure && model.password.isEmpty && model.email == "retained@example.com")
        }
        #expect(model.form.banner == .offline)
    }
    @Test func concurrentAttemptsAndEditingWhileBusyAreIgnored() async throws {
        let gate = IdentityGate()
        let session = AuthTestSession()
        let model = SignInModel(
            source: try authTestSource(), session: session, deviceIdentity: { await gate.wait() }, deviceName: "test",
            route: { _ in })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        let attempt = Task { await model.submitPassword() }
        while !model.form.busy { await Task.yield() }
        await model.submitPassword()
        await model.submitPasskey()
        model.editEmail("changed")
        model.editPassword("changed")
        await gate.resume()
        await attempt.value
        #expect(await session.accepted.count == 1 && model.email == "demo@example.com" && model.password.isEmpty)
    }
    @Test(arguments: [
        SessionFailure.credentialsUnavailable, .databaseUnavailable, .credentialWrite, .invalidResult, .superseded,
    ])
    func storeFailuresShowAndAnnounceTheServerBannerWithoutRouting(_ failure: SessionFailure) async throws {
        let session = AuthTestSession()
        await session.fail(failure)
        var routes: [Route] = []
        let model = SignInModel(
            source: try authTestSource(), session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test",
            assertionProvider: DeterministicAssertionProvider { _ in
                Base64URL.assertion(
                    credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                    signature: Data([4]), userHandle: nil)
            }, route: { routes.append($0) })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        await model.submitPassword()
        #expect(routes.isEmpty && model.form.banner == .server && model.password.isEmpty)
        #expect(model.sessionFailure == failure)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "en")) != nil)
        await model.submitPasskey()
        #expect(routes.isEmpty && model.form.banner == .server && !model.form.busy)
        #expect(model.sessionFailure == failure)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) != nil)
    }
    @Test func accountGatePrecedenceUsesAvailableAccountRecord() {
        func account(verified: Bool, accepted: String?, seen: Bool) -> SessionAccount {
            SessionAccount(
                id: "0199a3c0-0000-7000-8000-000000000000", name: "Test", email: "test@example.com",
                hasVerifiedEmail: verified,
                policies: AccountPolicies(termsVersion: "2", privacyVersion: "2", acceptedTermsVersion: accepted),
                walkthroughSeen: seen)
        }
        #expect(AuthNavigation.route(for: account(verified: false, accepted: nil, seen: false)) == .verify)
        #expect(AuthNavigation.route(for: account(verified: true, accepted: "1", seen: false)) == .terms)
        #expect(AuthNavigation.route(for: account(verified: true, accepted: "2", seen: false)) == .walkthrough)
        #expect(AuthNavigation.route(for: account(verified: true, accepted: "2", seen: true)) == .today)
    }

    @Test(arguments: Gate.allCases, [false, true])
    func committedSessionUsesStoredGateWithAndWithoutCancellation(_ storedGate: Gate, _ cancelAfterCommit: Bool)
        async throws
    {
        for method in ["password", "passkey", "twoFactor"] {
            let gate = AcceptedSessionSyncGate()
            let credentials = AcceptedSessionCredentials()
            let session = SessionController(
                credentials: credentials, accounts: AcceptedSessionAccounts(), requestSync: { _ in await gate.wait() })
            let readiness = StoredDataReadiness(controller: session) { id in
                AsyncThrowingStream {
                    $0.yield(StoredAccountReadiness(accountID: id, gate: storedGate, hasStoredData: false))
                    $0.finish()
                }
            }
            let navigator = AcceptedSessionNavigator()
            var verificationEpochs: [UInt64] = []
            let model = SignInModel(
                source: try authTestSource(twoFactor: method == "twoFactor"), session: session,
                deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test",
                assertionProvider: DeterministicAssertionProvider { _ in
                    Base64URL.assertion(
                        credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                        signature: Data([4]), userHandle: nil)
                },
                route: { _ in
                    #expect(Task.isCancelled == cancelAfterCommit)
                    await readiness.routeAcceptedSession(navigator: navigator) { epoch in
                        verificationEpochs.append(epoch)
                        navigator.navigate(to: .verify)
                    }
                })
            model.editEmail("demo@example.com")
            model.editPassword("Password123!")
            let request = Task {
                if method == "passkey" {
                    await model.submitPasskey()
                } else {
                    await model.submitPassword()
                    if method == "twoFactor" {
                        let challenge = model.twoFactor
                        #expect(challenge != nil)
                        #expect(await session.activeSession() == nil)
                        #expect(await credentials.data == nil)
                        challenge?.editCode("123456")
                        await challenge?.submit()
                        #expect(challenge?.code.isEmpty == true && challenge?.sessionFailure == nil)
                    }
                }
            }
            await gate.waitUntilEntered()
            let data = try #require(await credentials.data)
            let stored = try #require(StoredSession.parse(data))
            #expect(await session.presence == .signedIn(accountID: stored.accountId))
            #expect(navigator.routes.isEmpty)
            if cancelAfterCommit { request.cancel() }
            await gate.release()
            await request.value
            #expect(navigator.routes == [storedGate.route])
            let epoch = await session.epoch
            #expect(verificationEpochs == (storedGate == .verify ? [epoch] : []))
            #expect(model.password.isEmpty && !model.form.busy && model.form.banner == nil)
            #expect(model.sessionFailure == nil)
            #expect(await session.storedSession == stored)
        }
    }

    @Test(arguments: [Gate.verify, .terms], [false, true])
    func signOutDuringStoredGateReadPreventsStaleRouting(_ storedGate: Gate, _ cancelRequest: Bool) async throws {
        let gate = AcceptedSessionSyncGate()
        let session = SessionController(
            credentials: AcceptedSessionCredentials(), accounts: AcceptedSessionAccounts())
        let source = try authTestSource()
        let result = try await source.signIn(
            PasswordSignInInput(
                email: "demo@example.com", password: "Password123!",
                deviceID: "0199a3c0-0000-7000-8000-000000000001", deviceName: "test"))
        guard case .session(let accepted) = result else {
            Issue.record("Expected a session")
            return
        }
        try await session.accept(accepted)
        let readiness = StoredDataReadiness(controller: session) { id in
            await gate.wait()
            return AsyncThrowingStream {
                $0.yield(StoredAccountReadiness(accountID: id, gate: storedGate, hasStoredData: false))
                $0.finish()
            }
        }
        let navigator = AcceptedSessionNavigator()
        let request = Task {
            await readiness.routeAcceptedSession(navigator: navigator) { _ in Issue.record("Stale verification") }
        }
        await gate.waitUntilEntered()
        if cancelRequest { request.cancel() }
        _ = try await session.signOut(discardPending: true, unauthorized: true)
        navigator.navigate(to: .signIn)
        await gate.release()
        await request.value
        #expect(navigator.routes == [.signIn])
    }
}

@MainActor private final class AcceptedSessionNavigator: Navigator {
    private(set) var routes: [Route] = []
    func navigate(to route: Route) { routes.append(route) }
}

private actor AcceptedSessionCredentials: SessionStore {
    private(set) var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor AcceptedSessionAccounts: SessionAccountStore {
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) {}
    func close() {}
}

private actor AcceptedSessionSyncGate {
    private var entered = false
    private var released = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        entryWaiter?.resume()
        if !released { await withCheckedContinuation { releaseWaiter = $0 } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiter = $0 } }
    }
    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

actor IdentityGate {
    private var continuation: CheckedContinuation<String, Never>?
    private var resumed = false
    func wait() async -> String {
        if resumed { return "0199a3c0-0000-7000-8000-000000000001" }
        return await withCheckedContinuation { continuation = $0 }
    }
    func resume() {
        resumed = true
        continuation?.resume(returning: "0199a3c0-0000-7000-8000-000000000001")
        continuation = nil
    }
}

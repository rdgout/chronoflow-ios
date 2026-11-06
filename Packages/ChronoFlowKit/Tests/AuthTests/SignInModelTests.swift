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
    func fail(_ failure: SessionFailure) { self.failure = failure }
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
    return MockDataSource(seed: MockServerState(accounts: [account]), delay: { 0 }, sleep: { _ in })
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
        #expect(model.form.banner == nil)
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
    @Test func cancellationAndStoreFailureNeverRouteOrShowUndesignedBanner() async throws {
        let session = AuthTestSession()
        await session.fail(.databaseUnavailable)
        var routes: [Route] = []
        let model = SignInModel(
            source: try authTestSource(), session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", route: { routes.append($0) })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        await model.submitPassword()
        #expect(routes.isEmpty && model.form.banner == nil && model.password.isEmpty)
        #expect(model.sessionFailure == .databaseUnavailable)
        await model.submitPasskey()
        #expect(routes.isEmpty && model.form.banner == nil && !model.form.busy)
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

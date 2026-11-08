import AppCore
import Auth
import DataAccess
import Foundation
import Testing

private final class VerificationClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 1_800_000_000
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: time) } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
}

@MainActor struct VerifyEmailModelTests {
    private func registered(
        now: @escaping @Sendable () -> Date = { Date() }, sleep: @escaping APIClient.Sleep = { _ in }
    ) async throws -> (
        MockDataSource, SessionResult, SignedVerificationInput
    ) {
        let source = MockDataSource(seed: MockServerState(), now: now, delay: { 1 }, sleep: sleep)
        let result = try await source.signUp(
            RegisterInput(
                name: "Name", email: "new@example.com", password: "NewPassword123!",
                passwordConfirmation: "NewPassword123!", deviceID: "0199a3c0-0000-7000-8000-000000000001",
                deviceName: "test", language: .nl))
        guard case .verification(_, _, _, let input) = try await source.inbox().last else {
            throw DataFailure.server(status: nil)
        }
        return (source, result, input)
    }
    @Test func signedMockMailPersistsOnceAndRoutesOnlyForMatchingAccountEmailEpoch() async throws {
        let (source, result, input) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 7)
        var stored: [VerificationContext] = []
        var routes = 0
        let model = VerifyEmailModel(
            context: context, source: source, current: { context },
            persist: {
                stored.append($0)
                return true
            }, route: { routes += 1 }, discard: {})
        model.receiveLink(input)
        await model.activate()
        #expect(stored == [context] && routes == 1 && model.state == .waiting)
        #expect(try await source.fetchIdentity().hasVerifiedEmail)
        model.cancel()
        await model.activate()
        #expect(stored == [context] && routes == 1)
    }
    @Test func invalidExpiredForeignAndTamperedLinksUseFailedAndRetryChecksStatus() async throws {
        let (source, result, input) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 1)
        var tampered = input
        tampered.signature = String(repeating: "0", count: 64)
        var expired = input
        expired.expires = 1
        var foreign = input
        foreign.id = "0199a3c0-0000-7000-8000-000000000099"
        for link in [nil, tampered, expired, foreign] {
            let model = VerifyEmailModel(
                context: context, source: source, current: { context },
                persist: { _ in
                    Issue.record("Invalid link persisted")
                    return true
                }, route: { Issue.record("Invalid link routed") }, discard: {})
            model.receiveLink(link)
            await model.activate()
            #expect(model.state == .failed)
            await model.check()
            #expect(model.state == .waiting && model.hasStatus)
        }
    }
    @Test func resendDeadlineSurvivesIdentityRefreshActivationAndBackgroundTime() async throws {
        let clock = VerificationClock()
        let (source, result, _) = try await registered(now: { clock.now() })
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 2)
        let model = VerifyEmailModel(
            context: context, source: source, now: { clock.now() }, current: { context }, persist: { _ in true },
            route: {}, discard: {})
        await model.activate()
        #expect(model.canResend)
        await model.resend()
        #expect(model.form.banner == .locked && model.remaining == 60 && !model.canResend)
        await model.activate()
        #expect(model.remaining == 60)
        clock.advance(42)
        await model.activate()
        #expect(model.remaining == 18 && !model.canResend)
        await model.resend()
        #expect(try await source.inbox().count == 1)
        clock.advance(18)
        model.tick()
        #expect(model.canResend)
        await model.resend()
        #expect(model.remaining == 60 && model.form.failure == nil)
        #expect(try await source.inbox().count == 2)
        #expect(
            AuthCopy.resendCountdown(seconds: 42, locale: Locale(identifier: "nl"))
                == "Je kunt de link over 0:42 opnieuw versturen.")
    }
    @Test func activationAfterWebVerificationAndEmailAppReturnObserveTheServer() async throws {
        let (source, result, input) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 3)
        var routes = 0
        let model = VerifyEmailModel(
            context: context, source: source, current: { context }, persist: { _ in true }, route: { routes += 1 },
            discard: {})
        await model.activate()
        #expect(routes == 0 && model.state == .waiting)
        _ = try await source.verifyEmail(input)
        await model.activate()
        #expect(routes == 1)
        var opened = 0
        await model.openEmail { url in
            #expect(url.absoluteString == "message://")
            opened += 1
            return false
        }
        #expect(opened == 1 && routes == 1)
    }
    @Test func staleSessionOrEmailAndCanceledResponsesCannotPersistOrRoute() async throws {
        let (source, result, input) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 4)
        for next in [
            nil, VerificationContext(accountID: "0199a3c0-0000-7000-8000-000000000099", email: context.email, epoch: 4),
            VerificationContext(accountID: context.accountID, email: "changed@example.com", epoch: 4),
            VerificationContext(accountID: context.accountID, email: context.email, epoch: 5),
        ] {
            var current: VerificationContext? = context
            let model = VerifyEmailModel(
                context: context, source: source, current: { current },
                persist: { _ in
                    Issue.record("Stale write")
                    return true
                }, route: { Issue.record("Stale route") }, discard: {})
            current = next
            model.receiveLink(input)
            await model.check()
            #expect(!model.hasStatus)
        }
        let gate = ForgotRequestGate()
        let delayed = MockDataSource(delay: { 1 }, sleep: { _ in await gate.wait() })
        let model = VerifyEmailModel(
            context: context, source: delayed, current: { context },
            persist: { _ in
                Issue.record("Canceled write")
                return true
            }, route: {}, discard: {})
        let task = Task { await model.check() }
        await gate.waitUntilEntered()
        model.cancel()
        task.cancel()
        await gate.release()
        await task.value
        #expect(!model.hasStatus && model.form.failure == nil)
    }
    @Test func responseArrivingAfterEmailChangeCannotWriteAndStaleBackCannotDiscard() async throws {
        let gate = VerificationRequestGate()
        let (source, result, input) = try await registered(sleep: { _ in await gate.pause() })
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 9)
        var current: VerificationContext? = context
        let model = VerifyEmailModel(
            context: context, source: source, current: { current },
            persist: { _ in
                Issue.record("Late write")
                return true
            }, route: { Issue.record("Late route") }, discard: { Issue.record("Stale Back wiped another account") })
        model.receiveLink(input)
        await gate.arm()
        let task = Task { await model.check() }
        await gate.waitUntilEntered()
        current = VerificationContext(accountID: context.accountID, email: "changed@example.com", epoch: 9)
        await gate.release()
        await task.value
        #expect(!model.hasStatus)
        await model.signOut()
        #expect(model.isActive)
    }

    @Test func serverOfflineUnverifiedFailureDoesNotLoopAndBackExplicitlyDiscards() async throws {
        let (source, result, _) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 6)
        var discarded = 0
        let model = VerifyEmailModel(
            context: context, source: source, current: { context }, persist: { _ in true }, route: {},
            discard: {
                discarded += 1
                try await source.signOut()
            })
        for failure in [DataFailure.offline, .server(status: 503), .emailUnverified(status: 403)] {
            await source.failNext(method: .verificationStatus, error: failure)
            await model.check()
            #expect(model.state == .failed)
            #expect(model.form.banner == (failure == .offline ? .offline : .server))
            #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) != nil)
        }
        await model.signOut()
        #expect(discarded == 1 && !model.isActive)
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
    }

    @Test(arguments: [
        SessionFailure.credentialsUnavailable, .databaseUnavailable, .credentialWrite, .invalidResult, .superseded,
    ])
    func sessionFailuresAreVisibleOnCheckActivationResendAndSignOut(_ failure: SessionFailure) async throws {
        for action in ["check", "activate", "resend", "signOut"] {
            let (source, result, input) = try await registered()
            let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 8)
            var routes = 0
            var shouldFail = true
            let model = VerifyEmailModel(
                context: context, source: source, current: { context },
                persist: { _ in
                    if shouldFail { throw failure }
                    return true
                }, route: { routes += 1 }, discard: { throw failure })
            await model.activate()
            _ = try await source.verifyEmail(input)
            switch action {
            case "activate": await model.activate()
            case "resend": await model.resend()
            case "signOut": await model.signOut()
            default: await model.check()
            }
            #expect(model.sessionFailure == failure && model.form.banner == .server && routes == 0)
            #expect(model.form.takeAnnouncement(locale: Locale(identifier: "en")) != nil)
            shouldFail = false
            await model.check()
            #expect(model.sessionFailure == nil && model.form.failure == nil && routes == 1)
        }
    }

    @Test func offlineResendShowsAndAnnouncesTheConnectionBanner() async throws {
        let (source, result, _) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 10)
        let model = VerifyEmailModel(
            context: context, source: source, current: { context }, persist: { _ in true }, route: {}, discard: {})
        await model.activate()
        await source.setOffline(true)
        await model.resend()
        #expect(model.form.banner == .offline && !model.form.busy && model.canResend)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) == "Verbinding nodig")
    }

    @Test func repeatedSignOutFailuresEachShowAndAnnounceTheConnectionBanner() async throws {
        let (source, result, _) = try await registered()
        let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 11)
        let model = VerifyEmailModel(
            context: context, source: source, current: { context }, persist: { _ in true }, route: {},
            discard: { throw DataFailure.offline })
        for _ in 0..<2 {
            await model.signOut()
            #expect(model.form.banner == .offline && model.signOutFailure == .offline && model.isActive)
            #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) == "Verbinding nodig")
            #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) == nil)
        }
    }
}

private actor VerificationRequestGate {
    private var armed = false
    private let gate = ForgotRequestGate()
    func arm() { armed = true }
    func pause() async {
        if armed {
            armed = false
            await gate.wait()
        }
    }
    func waitUntilEntered() async { await gate.waitUntilEntered() }
    func release() async { await gate.release() }
}

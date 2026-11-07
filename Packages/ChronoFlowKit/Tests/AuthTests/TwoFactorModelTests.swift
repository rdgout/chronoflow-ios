import AppCore
import Auth
import DataAccess
import Foundation
import Testing

@MainActor struct TwoFactorModelTests {
    @Test(arguments: [false, true]) func emptyProofShowsOnlyTheActiveFieldError(recovery: Bool) async throws {
        let model = try #require(await challenged(twoFactorSource()).twoFactor)
        if recovery { model.toggleMode() }
        await model.submit()
        let messages = [
            "code": FieldMessage(key: "Enter the 6-digit code from your authenticator app."),
            "recovery_code": FieldMessage(
                key: "Enter one of the recovery codes you saved when you set up two-factor authentication."),
        ]
        #expect(model.form.failure == .validation(fields: messages, status: 422))
        #expect(model.form.fields == [model.field: messages[model.field]!])
        #expect(model.form.banner == nil && model.code.isEmpty && !model.form.busy)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "en")) == nil)
    }

    @Test(arguments: [true, false]) func latestCodeAcceptsThroughPasswordSessionPath(_ verified: Bool) async throws {
        let source = try twoFactorSource(verified: verified, code: "654321")
        let session = AuthTestSession()
        var routes: [Route] = []
        let signIn = try await challenged(source, session: session) { routes.append($0) }
        let model = try #require(signIn.twoFactor)
        #expect(await session.accepted.isEmpty && routes.isEmpty && signIn.password.isEmpty)
        await model.submit()
        #expect(model.form.fields["code"]?.key == "Enter the 6-digit code from your authenticator app.")
        model.editCode("123456")
        await model.submit()
        #expect(model.form.fields["code"]?.key == "The authentication code was not accepted. Try again.")
        #expect(model.code.isEmpty && model.form.banner == nil && !model.form.busy)
        model.editCode("654321")
        #expect(await session.accepted.isEmpty)
        await model.submit()
        await model.submit()
        #expect(await session.accepted.count == 1)
        #expect(routes == [verified ? .today : .verify])
        #expect(model.code.isEmpty && signIn.navigation.challengeID == nil)
    }

    @Test func numericInputFiltersPastesAndAutoFillWithoutSubmitting() async throws {
        let session = AuthTestSession()
        let signIn = try await challenged(twoFactorSource(), session: session)
        let model = try #require(signIn.twoFactor)
        model.editCode("a12 ٣b345678")
        #expect(model.code == "123456")
        #expect(await session.accepted.isEmpty && !model.form.busy)
        model.toggleMode()
        model.editCode("AbCdEf1234-GhIjKl5678")
        #expect(model.code == "AbCdEf1234-GhIjKl5678")
    }

    @Test func recoveryIsSingleUseAndModeToggleClearsFeedback() async throws {
        let source = try twoFactorSource()
        let session = AuthTestSession()
        let first = try await challenged(source, session: session)
        let model = try #require(first.twoFactor)
        await model.submit()
        model.toggleMode()
        #expect(model.mode == .recovery && model.code.isEmpty && model.form.fields.isEmpty)
        await model.submit()
        #expect(
            model.form.fields["recovery_code"]?.key
                == "Enter one of the recovery codes you saved when you set up two-factor authentication.")
        model.editCode("wrong")
        await model.submit()
        #expect(model.code.isEmpty && model.form.fields["recovery_code"] != nil && model.form.banner == nil)
        model.editCode("AbCdEf1234-GhIjKl5678")
        await model.submit()
        #expect(await session.accepted.count == 1)
        let second = try await challenged(source, session: session)
        let next = try #require(second.twoFactor)
        next.toggleMode()
        next.editCode("AbCdEf1234-GhIjKl5678")
        await next.submit()
        #expect(
            next.form.fields["recovery_code"]?.key == "This recovery code was not accepted. Try another saved code.")
        #expect(next.code.isEmpty && next.form.banner == nil)
        next.toggleMode()
        #expect(next.mode == .code && next.form.fields.isEmpty)
    }

    @Test func expiryAndFiveFailuresKeepTheReturnedFieldState() async throws {
        for expired in [true, false] {
            let clock = TwoFactorClock()
            let session = AuthTestSession()
            let signIn = try await challenged(twoFactorSource(now: clock.now), session: session)
            let model = try #require(signIn.twoFactor)
            if expired {
                clock.advance(300)
            } else {
                for _ in 0..<5 {
                    model.editCode("000000")
                    await model.submit()
                }
                clock.advance(60)
            }
            model.editCode("123456")
            await model.submit()
            #expect(model.form.fields["code"]?.key == "The authentication code was not accepted. Try again.")
            #expect(model.form.banner == nil && model.code.isEmpty && !model.form.busy)
            #expect(await session.accepted.isEmpty)
        }
    }

    @Test func throttleServerOfflineAndHiddenFieldsUseKeptDefaults() async throws {
        let source = try twoFactorSource()
        let signIn = try await challenged(source)
        let model = try #require(signIn.twoFactor)
        for failure in [
            DataFailure.throttled(retryAfterSeconds: 73, status: 429), .server(status: 503), .offline,
            .validation(fields: ["challengeId": FieldMessage(key: "Please fill this in.")], status: 422),
            .validation(fields: ["recovery_code": FieldMessage(key: "Please fill this in.")], status: 422),
        ] {
            model.editCode("123456")
            await source.failNext(method: .completeTwoFactor, error: failure)
            await model.submit()
            #expect(model.form.failure == failure && model.code.isEmpty && !model.form.busy)
            #expect(
                model.form.banner
                    == (failure == .offline
                        ? nil : failure == .throttled(retryAfterSeconds: 73, status: 429) ? .locked : .server))
            if model.form.banner == .locked {
                #expect(model.form.retryAfterSeconds == 73)
                #expect(
                    model.form.takeAnnouncement(locale: Locale(identifier: "nl"))
                        == "Te veel pogingen. Wacht een paar minuten voordat je het opnieuw probeert.")
            }
            model.editCode("1")
            #expect(model.form.banner == nil)
        }
    }

    @Test func doubleSubmitBusyEditsToggleAndBackDiscardLateSuccess() async throws {
        let gate = TwoFactorGate()
        let session = AuthTestSession()
        let signIn = try await challenged(twoFactorSource(sleep: { _ in await gate.wait() }), session: session)
        let model = try #require(signIn.twoFactor)
        model.editCode("123456")
        await gate.arm()
        let attempt = Task { await model.submit() }
        await gate.waitUntilEntered()
        await model.submit()
        model.editCode("654321")
        model.toggleMode()
        #expect(model.code == "123456" && model.mode == .code && model.form.busy)
        model.cancel()
        #expect(model.code.isEmpty && signIn.navigation.challengeID == nil && signIn.navigation.path.isEmpty)
        await gate.release()
        await attempt.value
        #expect(await session.accepted.isEmpty)
        #expect(!model.form.busy && model.form.failure == nil)
        signIn.navigation.twoFactor(challengeID: "new-challenge")
        model.cancel()
        #expect(signIn.navigation.challengeID == "new-challenge" && signIn.navigation.path == [.twoFactor])
    }

    @Test func taskCancellationClearsCodeWithoutPresentationOrAcceptance() async throws {
        let gate = TwoFactorGate()
        let session = AuthTestSession()
        let signIn = try await challenged(twoFactorSource(sleep: { _ in await gate.wait() }), session: session)
        let model = try #require(signIn.twoFactor)
        model.editCode("123456")
        await gate.arm()
        let attempt = Task { await model.submit() }
        await gate.waitUntilEntered()
        attempt.cancel()
        await gate.release()
        await attempt.value
        #expect(model.code.isEmpty && model.form.failure == nil && !model.form.busy)
        #expect(await session.accepted.isEmpty)
    }

    @Test func missingChallengeReturnsToSignInAndNewNavigationCannotRestoreSecrets() async throws {
        let session = AuthTestSession()
        let signIn = try await challenged(twoFactorSource(), session: session)
        let model = try #require(signIn.twoFactor)
        model.editCode("123456")
        signIn.navigation.discardChallenge()
        await model.submit()
        #expect(signIn.navigation.path.isEmpty && model.code.isEmpty)
        let fresh = AuthNavigation()
        fresh.push(.twoFactor)
        let missing = TwoFactorModel(source: try twoFactorSource(), navigation: fresh) { _ in
            Issue.record("Missing challenge must not accept")
        }
        missing.validateChallenge()
        #expect(fresh.path.isEmpty && fresh.challengeID == nil && missing.code.isEmpty)
        fresh.twoFactor(challengeID: " \n")
        #expect(fresh.path.isEmpty && fresh.challengeID == nil)
        #expect(await session.accepted.isEmpty)
    }

    @Test func sessionStorageFailureRemainsTypedAndNeverRoutes() async throws {
        let session = AuthTestSession()
        await session.fail(.databaseUnavailable)
        let signIn = try await challenged(twoFactorSource(), session: session)
        let model = try #require(signIn.twoFactor)
        model.editCode("123456")
        await model.submit()
        #expect(model.sessionFailure == .databaseUnavailable && model.form.banner == nil && model.code.isEmpty)
        #expect(await session.accepted.isEmpty)
    }

    @Test func onlySessionAcceptancePersistsATokenAndNeverTheChallengeOrProof() async throws {
        let credentials = TwoFactorCredentials()
        let accounts = TwoFactorAccounts()
        let session = SessionController(credentials: credentials, accounts: accounts)
        let signIn = try await challenged(twoFactorSource(), session: session)
        let challenge = try #require(signIn.navigation.challengeID)
        let model = try #require(signIn.twoFactor)
        model.editCode("000000")
        await model.submit()
        #expect(await credentials.read() == nil)
        #expect(await accounts.records.isEmpty)
        model.toggleMode()
        model.editCode("AbCdEf1234-GhIjKl5678")
        #expect(await credentials.read() == nil)
        await model.submit()
        let stored = try #require(await credentials.read())
        let sessionRecord = try JSONDecoder().decode(StoredSession.self, from: stored)
        #expect(!sessionRecord.token.isEmpty)
        let storedObject = try #require(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(Set(storedObject.keys) == ["token", "accountId"])
        let accountRecords = await accounts.records
        let records = String(decoding: stored + accountRecords, as: UTF8.self)
        #expect(!records.contains(challenge) && !records.contains("AbCdEf1234-GhIjKl5678"))
        #expect(model.code.isEmpty && signIn.navigation.challengeID == nil)
    }

    @Test func backendMessagesLocalizeOnlyUnderTheDisplayedModeAndAnnouncementsAreConsumedOnce() async throws {
        let model = try #require(await challenged(twoFactorSource()).twoFactor)
        for (recovery, key, dutch) in [
            (
                false, "Enter the 6-digit code from your authenticator app.",
                "Vul de 6-cijferige code uit je authenticator-app in."
            ),
            (
                false, "The authentication code was not accepted. Try again.",
                "De verificatiecode is niet geaccepteerd. Probeer het opnieuw."
            ),
            (
                true, "Enter one of the recovery codes you saved when you set up two-factor authentication.",
                "Vul een van de herstelcodes in die je hebt bewaard bij het instellen van tweefactorauthenticatie."
            ),
            (
                true, "This recovery code was not accepted. Try another saved code.",
                "Deze herstelcode is niet geaccepteerd. Probeer een andere bewaarde code."
            ),
        ] {
            if (model.mode == .recovery) != recovery { model.toggleMode() }
            let message = FieldMessage(key: key)
            model.form.receive(.validation(fields: [model.field: message], status: 422))
            #expect(model.form.fields[model.field] == message && model.form.banner == nil)
            #expect(AuthCopy.field(message, locale: Locale(identifier: "en")) == key)
            #expect(AuthCopy.field(message, locale: Locale(identifier: "nl")) == dutch)
            for (language, expected) in [
                ("en", "Too many attempts. Wait a few minutes before you try again."),
                ("nl", "Te veel pogingen. Wacht een paar minuten voordat je het opnieuw probeert."),
            ] {
                model.form.receive(.throttled(retryAfterSeconds: 40, status: 429))
                let locale = Locale(identifier: language)
                #expect(model.form.takeAnnouncement(locale: locale) == expected)
                #expect(model.form.takeAnnouncement(locale: locale) == nil)
                model.toggleMode()
                #expect(model.form.takeAnnouncement(locale: locale) == nil && model.form.fields.isEmpty)
            }
        }
    }
}

@MainActor private func challenged(
    _ source: MockDataSource, session: any SessionControlling = AuthTestSession(),
    route: @escaping @MainActor (Route) async -> Void = { _ in }
) async throws -> SignInModel {
    let model = SignInModel(
        source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
        deviceName: "test", route: route)
    model.editEmail("twofactor@example.com")
    model.editPassword("password")
    await model.submitPassword()
    #expect(model.navigation.path == [.twoFactor])
    return model
}

private func twoFactorSource(
    verified: Bool = true, code: String = "123456", now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping APIClient.Sleep = { _ in }
) throws -> MockDataSource {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    var snapshot = try JSONDecoder().decode(
        AccountSnapshot.self,
        from: Data(contentsOf: root.appending(path: "DataAccessTests/Fixtures/account/snapshot.json")))
    snapshot.email = "twofactor@example.com"
    snapshot.hasVerifiedEmail = verified
    snapshot.settings.policies = AccountPolicies(termsVersion: "1", privacyVersion: "1", acceptedTermsVersion: "1")
    return MockDataSource(
        seed: MockServerState(accounts: [
            MockServerAccount(
                snapshot: snapshot, password: "password", twoFactorCode: code,
                recoveryCodes: ["AbCdEf1234-GhIjKl5678"], walkthroughSeen: true)
        ]),
        now: now, delay: { 0 }, sleep: sleep)
}

private final class TwoFactorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { instant } }
    func advance(_ seconds: TimeInterval) { lock.withLock { instant += seconds } }
}

private actor TwoFactorGate {
    private var armed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var entry: CheckedContinuation<Void, Never>?
    func arm() { armed = true }
    func wait() async {
        guard armed else { return }
        await withCheckedContinuation {
            continuation = $0
            entry?.resume()
            entry = nil
        }
    }
    func waitUntilEntered() async {
        if continuation == nil { await withCheckedContinuation { entry = $0 } }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor TwoFactorCredentials: SessionStore {
    private var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) { self.data = data }
    func delete() { data = nil }
}

private actor TwoFactorAccounts: SessionAccountStore {
    private(set) var records = Data()
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) throws { records = try JSONEncoder().encode(account) }
    func close() {}
}

import AppCore
import Auth
import DataAccess
import Foundation
import Testing

struct PasskeyEncodingTests {
    @Test func binaryBytesRoundTripWithoutUTF8OrPaddingAndAllDTOFieldsUseBase64URL() throws {
        let bytes = Data((0...255).map(UInt8.init))
        let encoded = Base64URL.encode(bytes)
        #expect(!encoded.contains("=") && !encoded.contains("+") && !encoded.contains("/"))
        #expect(try Base64URL.decode(encoded) == bytes)
        for bad in ["", "a", "AQ==", "AQ+", "AQ/", "AR", "é", "a b"] {
            #expect(throws: PasskeyFailure.invalidEncoding) { try Base64URL.decode(bad) }
        }
        let assertion = Base64URL.assertion(
            credentialID: bytes, clientDataJSON: bytes, authenticatorData: bytes, signature: bytes, userHandle: bytes)
        #expect(assertion.id == encoded && assertion.rawId == encoded && assertion.type == .publicKey)
        #expect(
            assertion.response.clientDataJSON == encoded && assertion.response.authenticatorData == encoded
                && assertion.response.signature == encoded && assertion.response.userHandle == encoded)
        let absent = Base64URL.assertion(
            credentialID: bytes, clientDataJSON: bytes, authenticatorData: bytes, signature: bytes, userHandle: nil)
        #expect(absent.response.userHandle == nil)
        let decoded = try JSONDecoder().decode(ApiPasskeyAssertion.self, from: JSONEncoder().encode(assertion))
        #expect(decoded == assertion)
    }
    @Test func passkeyFieldFailuresUseOnlyDesignedBannerAndNeverLeakServerCopy() {
        for (field, key) in [
            ("credential", "We couldn't sign you in with that passkey. Please try again."),
            ("challengeId", "The passkey request expired. Please try again."),
        ] {
            let mapping = AuthFailureMapping(
                .validation(fields: [field: FieldMessage(key: key)], status: 422),
                displayedFields: ["email", "password"])
            #expect(mapping.banner == .server && mapping.fields.isEmpty)
        }
    }
}

@MainActor struct PasskeySignInTests {
    @Test(arguments: [0, 1, 2]) func mockPasskeyAcceptsVerifiedUnverifiedAndTwoFactorAccountsDirectly(_ scenario: Int)
        async throws
    {
        let source = try passkeySource(verified: scenario != 1, twoFactor: scenario == 2)
        let session = AuthTestSession()
        var routes: [Route] = []
        let provider = DeterministicAssertionProvider { challenge in
            #expect(challenge.options.rpId == "app.chronoflow.net" && challenge.options.userVerification == .required)
            let challengeBytes = try Base64URL.decode(challenge.options.challenge)
            #expect(challengeBytes.count == 32)
            return testAssertion()
        }
        let model = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", assertionProvider: provider, route: { routes.append($0) })
        await model.submitPasskey()
        #expect(await session.accepted.count == 1)
        #expect(routes == [scenario == 1 ? .verify : .today])
        #expect(model.navigation.challengeID == nil && model.navigation.path.isEmpty)
    }
    @Test func canceledPromptIsSilentAndRetryAlwaysGetsFreshOptions() async throws {
        let source = try passkeySource()
        let session = AuthTestSession()
        var challenges: [String] = []
        let provider = DeterministicAssertionProvider { challenge in
            challenges.append(challenge.challengeId)
            if challenges.count == 1 { throw PasskeyFailure.canceled }
            return testAssertion()
        }
        let model = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", assertionProvider: provider, route: { _ in })
        await model.submitPasskey()
        #expect(!model.form.busy && model.form.banner == nil && model.form.failure == nil)
        #expect(await session.accepted.isEmpty)
        await model.submitPasskey()
        #expect(challenges.count == 2 && challenges[0] != challenges[1])
        #expect(await session.accepted.count == 1)
    }
    @Test func consumedExpiredCredentialThrottleServerAndOfflineFailuresRetryWithoutSession() async throws {
        let source = try passkeySource()
        let session = AuthTestSession()
        var challenges: Set<String> = []
        let model = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test",
            assertionProvider: DeterministicAssertionProvider { challenge in
                #expect(challenges.insert(challenge.challengeId).inserted)
                return testAssertion()
            }, route: { _ in })
        for failure in [
            DataFailure.validation(
                fields: ["challengeId": FieldMessage(key: "The passkey request expired. Please try again.")],
                status: 422),
            .validation(
                fields: [
                    "credential": FieldMessage(key: "We couldn't sign you in with that passkey. Please try again.")
                ], status: 422),
            .throttled(retryAfterSeconds: 87, status: 429), .server(status: 500), .offline,
        ] {
            await source.failNext(method: .passkeyLogin, error: failure)
            await model.submitPasskey()
            #expect(model.form.failure == failure && !model.form.busy)
            #expect(await session.accepted.isEmpty)
        }
        await model.submitPasskey()
        #expect(await session.accepted.count == 1)
    }
    @Test func failedCredentialConsumesChallengeAndRetryFetchesAnother() async throws {
        let source = try passkeySource()
        let session = AuthTestSession()
        var challenges: [ApiPasskeyChallenge] = []
        let provider = DeterministicAssertionProvider { challenge in
            challenges.append(challenge)
            var assertion = testAssertion()
            if challenges.count == 1 {
                assertion.id = "Ag"
                assertion.rawId = "Ag"
            }
            return assertion
        }
        let model = SignInModel(
            source: source, session: session,
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test",
            assertionProvider: provider, route: { _ in })
        await model.submitPasskey()
        #expect(model.form.banner == .server)
        let used = try #require(challenges.first)
        await #expect(
            throws: DataFailure.validation(
                fields: ["challengeId": FieldMessage(key: "The passkey request expired. Please try again.")],
                status: 422)
        ) {
            try await source.passkeyLogin(
                ApiPasskeyLoginInput(
                    challengeId: used.challengeId,
                    credential: testAssertion(), deviceID: "0199a3c0-0000-7000-8000-000000000001", deviceName: "test"))
        }
        await model.submitPasskey()
        #expect(challenges.count == 2 && challenges[0].challengeId != challenges[1].challengeId)
        #expect(await session.accepted.count == 1)
    }

    @Test func taskCancellationAfterAssertionNeverAcceptsOrCallsLogin() async throws {
        let source = try passkeySource()
        let session = AuthTestSession()
        let provider = DeterministicAssertionProvider { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return testAssertion()
        }
        let model = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", assertionProvider: provider, route: { _ in Issue.record("Canceled route") })
        await Task { await model.submitPasskey() }.value
        #expect(await session.accepted.isEmpty)
        #expect(model.form.banner == nil && !model.form.busy)
    }
}

@MainActor private func testAssertion() -> ApiPasskeyAssertion {
    Base64URL.assertion(
        credentialID: Data([1]), clientDataJSON: Data("{\"type\":\"webauthn.get\"}".utf8), authenticatorData: Data([2]),
        signature: Data([3]), userHandle: nil)
}
private func passkeySource(verified: Bool = true, twoFactor: Bool = false) throws -> MockDataSource {
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

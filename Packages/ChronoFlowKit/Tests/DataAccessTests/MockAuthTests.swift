import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockAuthTests {
    @Test func latencyOfflineAndFailOnce() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        await source.setOffline(true)
        await source.failNext(method: .signIn, error: .server(status: 503))
        await #expect(throws: DataFailure.offline) { try await source.signIn(passwordInput()) }
        await source.setOffline(false)
        await #expect(throws: DataFailure.server(status: 503)) { try await source.signIn(passwordInput()) }
        _ = try await login(source)
        #expect(clock.delays.count == 3 && clock.delays.allSatisfy { (0.3...0.8).contains($0) })
        for delay in [-1.0, 0.3, 0.8, 10] {
            let clamped = MockDataSource(now: clock.now, delay: { delay }, sleep: clock.sleep)
            await #expect(throws: DataFailure.unauthorized(status: 401)) { try await clamped.fetchIdentity() }
        }
        #expect(clock.delays.suffix(4) == [0.3, 0.3, 0.8, 0.8])
    }
    @Test func fiveAttemptsThenWindowReset() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        for _ in 0..<5 { _ = try await login(source) }
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) { try await login(source) }
        clock.advance(60)
        _ = try await login(source)
        await #expect(throws: (any Error).self) { try await source.signIn(passwordInput(password: "wrong")) }
    }
    @Test func twoFactorSingleUseAndRecoveryConsumption() async throws {
        let source = try mockSource()
        guard case .twoFactor(let challenge) = try await source.signIn(passwordInput(email: "twofactor@example.com"))
        else {
            Issue.record("Expected challenge")
            return
        }
        _ = try await source.completeTwoFactor(
            TwoFactorInput(challengeId: challenge, proof: .recoveryCode(fixtureRecovery)))
        await #expect(throws: (any Error).self) {
            try await source.completeTwoFactor(TwoFactorInput(challengeId: challenge, proof: .code("123456")))
        }
        guard case .twoFactor(let next) = try await source.signIn(passwordInput(email: "twofactor@example.com")) else {
            Issue.record("Expected challenge")
            return
        }
        await #expect(throws: (any Error).self) {
            try await source.completeTwoFactor(TwoFactorInput(challengeId: next, proof: .recoveryCode(fixtureRecovery)))
        }
        #expect(
            try await source.completeTwoFactor(TwoFactorInput(challengeId: next, proof: .code("123456"))).account.id
                == twoFactorID)
    }
    @Test func twoFactorExpiryAndFiveFailures() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        guard case .twoFactor(let challenge) = try await source.signIn(passwordInput(email: "twofactor@example.com"))
        else {
            Issue.record("Expected challenge")
            return
        }
        for _ in 0..<5 {
            await #expect(throws: (any Error).self) {
                try await source.completeTwoFactor(TwoFactorInput(challengeId: challenge, proof: .code("000000")))
            }
        }
        clock.advance(60)
        await #expect(throws: (any Error).self) {
            try await source.completeTwoFactor(TwoFactorInput(challengeId: challenge, proof: .code("123456")))
        }
        guard case .twoFactor(let next) = try await source.signIn(passwordInput(email: "twofactor@example.com")) else {
            Issue.record("Expected challenge")
            return
        }
        clock.advance(300)
        await #expect(throws: (any Error).self) {
            try await source.completeTwoFactor(TwoFactorInput(challengeId: next, proof: .code("123456")))
        }
    }
    @Test func registerDuplicateAndUnverifiedGate() async throws {
        let source = try mockSource()
        let session = try await source.signUp(registration())
        #expect(!session.account.hasVerifiedEmail)
        #expect(try await source.fetchIdentity().email == "new@example.com")
        await #expect(throws: DataFailure.emailUnverified(status: 403)) { try await source.fetchAccount() }
        await #expect(throws: DataFailure.emailUnverified(status: 403)) { try await source.fetchTrips() }
        await #expect(throws: (any Error).self) { try await source.signUp(registration("NEW@example.com")) }
        #expect(try await source.inbox().count == 1)
    }
    @Test func forgotNonEnumeratingResetRevokesAllTokensAndOnce() async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = try mockSource(clock: clock, store: store)
        let old = try await login(source)
        _ = try await login(source, device: twoFactorID)
        try await source.requestPasswordReset(email: "absent@example.com")
        #expect(try await source.inbox().isEmpty)
        try await source.requestPasswordReset(email: "demo@example.com")
        guard case .passwordReset(_, _, _, var input) = try #require(await source.inbox().last) else {
            Issue.record("Expected reset input")
            return
        }
        input.password = newPassword
        input.passwordConfirmation = newPassword
        try await source.resetPassword(input)
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
        let restoredOld = try mockSource(clock: clock, store: store, bearer: { old.token })
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await restoredOld.fetchIdentity() }
        await #expect(throws: (any Error).self) { try await source.resetPassword(input) }
        guard case .session = try await source.signIn(passwordInput(password: newPassword)) else {
            Issue.record("Expected session")
            return
        }
    }
    @Test func resetExpiryAndConfirmation() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        try await source.requestPasswordReset(email: "demo@example.com")
        guard case .passwordReset(_, _, _, var input) = try #require(await source.inbox().last) else {
            Issue.record("Expected reset")
            return
        }
        input.password = newPassword
        input.passwordConfirmation = "mismatch"
        await #expect(throws: (any Error).self) { try await source.resetPassword(input) }
        input.passwordConfirmation = newPassword
        clock.advance(3600)
        await #expect(
            throws: DataFailure.validation(
                fields: ["token": FieldMessage(key: "This password reset link is invalid or has expired.")], status: 422
            )
        ) { try await source.resetPassword(input) }
    }
    @Test func verificationResendTamperExpiryAndAccountBinding() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        _ = try await source.signUp(registration())
        #expect(try await source.verificationStatus().resendAfterSeconds == 0)
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) {
            try await source.resendVerificationEmail()
        }
        guard case .verification(_, _, _, let signed) = try #require(await source.inbox().last) else {
            Issue.record("Expected signed input")
            return
        }
        var tampered = signed
        tampered.hash = "tampered"
        await #expect(throws: (any Error).self) { try await source.verifyEmail(tampered) }
        tampered = signed
        tampered.signature = "tampered"
        await #expect(throws: (any Error).self) { try await source.verifyEmail(tampered) }
        _ = try await login(source)
        await #expect(throws: (any Error).self) { try await source.verifyEmail(signed) }
        guard case .session = try await source.signIn(passwordInput(email: "new@example.com", password: newPassword))
        else {
            Issue.record("Expected session")
            return
        }
        clock.advance(3601)
        await #expect(throws: (any Error).self) { try await source.verifyEmail(signed) }
        #expect(try await source.resendVerificationEmail().resendAfterSeconds == 60)
        guard case .verification(_, _, _, let fresh) = try #require(await source.inbox().last) else {
            Issue.record("Expected signed input")
            return
        }
        #expect(try await source.verifyEmail(fresh).hasVerifiedEmail)
        #expect(try await source.verifyEmail(fresh).hasVerifiedEmail)
        _ = try await source.fetchAccount()
    }
    @Test func passkeySingleUseInvalidDoesConsumeAndMalformedDoesNot() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        let options = try await source.passkeyOptions()
        #expect(options.challengeId.count == 64 && options.options.challenge.count == 43)
        #expect(try await source.passkeyLogin(passkeyInput(options)).account.id == demoID)
        await #expect(throws: (any Error).self) { try await source.passkeyLogin(passkeyInput(options)) }
        let failed = try await source.passkeyOptions()
        await #expect(throws: (any Error).self) {
            try await source.passkeyLogin(passkeyInput(failed, signature: "YmFk"))
        }
        await #expect(throws: (any Error).self) { try await source.passkeyLogin(passkeyInput(failed)) }
        clock.advance(60)
        let valid = try await source.passkeyOptions()
        var malformed = passkeyInput(valid)
        malformed.credential.rawId = "AQ=="
        await #expect(throws: (any Error).self) { try await source.passkeyLogin(malformed) }
        #expect(try await source.passkeyLogin(passkeyInput(valid)).account.id == demoID)
    }
    @Test func passkeyExpiryAndBypassesTwoFactorForUnverified() async throws {
        let clock = MockClock()
        var seed = try scenarioState()
        seed.accounts[twoFactorID]?.snapshot.hasVerifiedEmail = false
        let source = try mockSource(clock: clock, seed: seed)
        let options = try await source.passkeyOptions()
        let result = try await source.passkeyLogin(passkeyInput(options, credentialID: "AQ"))
        #expect(result.account.id == twoFactorID && !result.account.hasVerifiedEmail)
        let expired = try await source.passkeyOptions()
        clock.advance(120)
        await #expect(
            throws: DataFailure.validation(
                fields: ["challengeId": FieldMessage(key: "The passkey request expired. Please try again.")],
                status: 422)
        ) { try await source.passkeyLogin(passkeyInput(expired)) }
    }
    @Test func passkeyLimitsAndDefaultProviderRejects() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        for _ in 0..<10 { _ = try await source.passkeyOptions() }
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) {
            try await source.passkeyOptions()
        }
        clock.advance(60)
        let options = try await source.passkeyOptions()
        for _ in 0..<5 {
            await #expect(throws: (any Error).self) {
                try await source.passkeyLogin(passkeyInput(options, signature: "YmFk"))
            }
        }
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) {
            try await source.passkeyLogin(passkeyInput(options))
        }
        let denied = MockDataSource(seed: try scenarioState(), sleep: clock.sleep)
        let challenge = try await denied.passkeyOptions()
        await #expect(
            throws: DataFailure.validation(
                fields: [
                    "credential": FieldMessage(key: "We couldn't sign you in with that passkey. Please try again.")
                ], status: 422)
        ) { try await denied.passkeyLogin(passkeyInput(challenge)) }
    }
}

extension MockAuthTests {
    @Test func passkeyHourlyFailureLimiterCountsOnlyValidationFailures() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        let options = try await source.passkeyOptions()
        for _ in 0..<4 {
            for _ in 0..<5 {
                await #expect(throws: (any Error).self) {
                    try await source.passkeyLogin(passkeyInput(options, signature: "YmFk"))
                }
            }
            clock.advance(60)
        }
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 3360, status: 429)) {
            try await source.passkeyLogin(passkeyInput(options))
        }
        clock.advance(3360)
        _ = try await source.passkeyLogin(passkeyInput(try await source.passkeyOptions()))
    }
    @Test func passkeyIPLimitSpansCredentials() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock)
        let options = try await source.passkeyOptions()
        for index in 0..<20 {
            var input = passkeyInput(options)
            let encoded = Data([UInt8(index)]).base64EncodedString().replacingOccurrences(of: "=", with: "")
            input.credential.id = encoded
            input.credential.rawId = encoded
            input.credential.response.signature = "YmFk"
            await #expect(throws: (any Error).self) { try await source.passkeyLogin(input) }
        }
        var next = passkeyInput(options)
        next.credential.id = "FA"
        next.credential.rawId = "FA"
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 60, status: 429)) {
            try await source.passkeyLogin(next)
        }
    }
    @Test func newPasswordPolicyAndDeviceValidation() async throws {
        let source = try mockSource()
        for value in ["short", "alllowercase12!", "ALLUPPERCASE12!", "NoNumbersHere!", "NoSymbolsHere12"] {
            var input = registration()
            input.password = value
            input.passwordConfirmation = value
            await #expect(throws: (any Error).self) { try await source.signUp(input) }
        }
        let invalid = try mockSource()
        var input = registration()
        input.deviceID = "invalid"
        await #expect(throws: (any Error).self) { try await invalid.signUp(input) }
        input = registration()
        input.deviceName = String(repeating: "a", count: 256)
        await #expect(throws: (any Error).self) { try await invalid.signUp(input) }
        input = registration()
        input.name = ""
        await #expect(throws: (any Error).self) { try await invalid.signUp(input) }
        await #expect(throws: (any Error).self) { try await invalid.requestPasswordReset(email: "invalid") }
    }
    @Test func canceledMockCallNeverChangesState() async throws {
        let source = try mockSource()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await source.signUp(registration())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await source.inbox().isEmpty)
    }
}

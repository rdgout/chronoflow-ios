import AppCore
import Auth
import DataAccess
import Foundation
import Testing

@MainActor struct ResetPasswordModelTests {
    @Test func mockMailResetClearsSecretsRevokesSessionsAndCannotBeReused() async throws {
        let source = try authTestSource()
        _ = try await source.signIn(
            PasswordSignInInput(
                email: "demo@example.com", password: "Password123!", deviceID: "0199a3c0-0000-7000-8000-000000000001",
                deviceName: "test"))
        try await source.requestPasswordReset(email: "demo@example.com")
        guard case .passwordReset(_, _, _, let input) = try await source.inbox().last else {
            Issue.record("Missing mail")
            return
        }
        let navigation = AuthNavigation()
        navigation.push(.reset(ResetPasswordLink(token: input.token, email: input.email)))
        for reused in [false, true] {
            let model = ResetPasswordModel(
                link: ResetPasswordLink(token: input.token, email: input.email), source: source, navigation: navigation)
            model.editPassword("NewPassword123!")
            model.editConfirmation("NewPassword123!")
            await model.submit()
            #expect(model.state == (reused ? .expired : .done))
            #expect(model.password.isEmpty && model.confirmation.isEmpty && !model.form.busy)
            if !reused {
                model.backToSignIn()
                #expect(navigation.path.isEmpty)
            }
        }
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
    }
    @Test func missingInvalidAndServerFieldMessagesUseDesignedStates() async throws {
        let source = try authTestSource()
        #expect(
            ResetPasswordModel(
                link: ResetPasswordLink(token: "", email: ""), source: source, navigation: AuthNavigation()
            ).state == .expired)
        let model = ResetPasswordModel(
            link: ResetPasswordLink(token: "bad", email: "demo@example.com"), source: source,
            navigation: AuthNavigation())
        for (password, confirmation, field) in [
            ("short", "short", "password"), ("NewPassword123!", "different", "password_confirmation"),
        ] {
            model.editPassword(password)
            model.editConfirmation(confirmation)
            await model.submit()
            #expect(model.state == .form && model.form.fields[field] != nil)
            #expect(model.password.isEmpty && model.confirmation.isEmpty)
        }
        for failure in [DataFailure.offline, .server(status: 500), .throttled(retryAfterSeconds: 60, status: 429)] {
            await source.failNext(method: .resetPassword, error: failure)
            model.editPassword("NewPassword123!")
            model.editConfirmation("NewPassword123!")
            await model.submit()
            #expect(model.state == .form && model.form.failure == failure)
            #expect(model.password.isEmpty && model.confirmation.isEmpty)
        }
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit()
        #expect(model.state == .expired && model.recovery.email == "demo@example.com")
        model.recovery.editEmail("replacement@example.com")
        await model.recovery.submit()
        #expect(model.recovery.sentEmail == "replacement@example.com")
    }
    @Test func cancelAndDuplicateSubmissionIgnoreLateCompletion() async {
        let gate = ForgotRequestGate()
        let source = MockDataSource(delay: { 1 }, sleep: { _ in await gate.wait() })
        let model = ResetPasswordModel(
            link: ResetPasswordLink(token: "test", email: "demo@example.com"), source: source,
            navigation: AuthNavigation())
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        let task = Task { await model.submit() }
        await gate.waitUntilEntered()
        await model.submit()
        model.editPassword("ignored")
        #expect(model.password == "NewPassword123!")
        model.cancel()
        task.cancel()
        await gate.release()
        await task.value
        #expect(await gate.entries == 1)
        #expect(model.password.isEmpty && model.confirmation.isEmpty && model.form.failure == nil)
    }
}

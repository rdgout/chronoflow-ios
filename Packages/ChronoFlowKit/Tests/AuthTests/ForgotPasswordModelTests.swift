import AppCore
import Auth
import DataAccess
import Foundation
import Testing

@MainActor struct ForgotPasswordModelTests {
    @Test func existingAndUnknownAddressesHaveIdenticalSuccessWithoutASession() async throws {
        let source = try authTestSource()
        for email in ["demo@example.com", "unknown@example.com"] {
            let navigation = AuthNavigation()
            navigation.forgot()
            let model = ForgotPasswordModel(source: source, navigation: navigation)
            model.editEmail(email)
            await model.submit()
            #expect(model.sentEmail == email && model.form.failure == nil && !model.form.busy)
            #expect(navigation.path == [.forgot] && navigation.challengeID == nil)
            model.editEmail("later@example.com")
            await model.submit()
            #expect(model.email == "later@example.com" && model.sentEmail == email)
        }
        #expect(try await source.inbox().count == 1)
        await #expect(throws: DataFailure.unauthorized(status: 401)) { try await source.fetchIdentity() }
    }

    @Test func fieldServerThrottleOfflineAndHiddenFailuresKeepTheFormAndEmail() async throws {
        let source = try authTestSource()
        let model = ForgotPasswordModel(source: source, navigation: AuthNavigation(), email: "retained@example.com")
        let field = FieldMessage(key: "Please fill this in.")
        for (failure, banner) in [
            (DataFailure.validation(fields: ["email": field], status: 422), nil),
            (.server(status: 503), AuthBannerKind.server),
            (.throttled(retryAfterSeconds: 73, status: 429), .locked),
            (.offline, nil),
            (.validation(fields: ["hidden": field], status: 422), .server),
            (.validation(fields: ["email": FieldMessage(key: "Untranslated server text")], status: 422), .server),
        ] {
            await source.failNext(method: .requestPasswordReset, error: failure)
            await model.submit()
            #expect(model.form.failure == failure && model.form.banner == banner)
            #expect(model.email == "retained@example.com" && model.sentEmail == nil && !model.form.busy)
            let fields = model.form.fields
            model.editEmail(model.email)
            #expect(model.form.failure == failure && model.form.banner == banner)
            #expect(model.form.fields == fields)
            if banner == .locked {
                #expect(model.form.retryAfterSeconds == 73)
                #expect(
                    model.form.takeAnnouncement(locale: Locale(identifier: "nl"))
                        == "Te veel verzoeken. Wacht een paar minuten voordat je een nieuwe link aanvraagt.")
                #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) == nil)
            }
            model.editEmail("edited@example.com")
            #expect(model.form.failure == nil && model.form.banner == nil && model.form.fields.isEmpty)
            model.editEmail("retained@example.com")
        }
    }

    @Test func serverValidatesBlankAndMalformedEmailWithoutClientValidation() async throws {
        let source = try authTestSource()
        let model = ForgotPasswordModel(source: source, navigation: AuthNavigation())
        for (email, message) in [
            ("", "Please fill this in."), ("   ", "Please fill this in."),
            ("invalid", "Enter a valid email address, like name@example.com."),
        ] {
            model.editEmail(email)
            await model.submit()
            #expect(model.form.fields["email"]?.key == message)
            #expect(model.form.banner == nil && model.sentEmail == nil)
        }
    }

    @Test func busyLockIgnoresEditsAndDuplicateTapOrReturnAndCapturesSubmittedEmail() async {
        let gate = ForgotRequestGate()
        let source = MockDataSource(delay: { 1 }, sleep: { _ in await gate.wait() })
        let model = ForgotPasswordModel(source: source, navigation: AuthNavigation(), email: "unknown@example.com")
        let attempt = Task { await model.submit() }
        await gate.waitUntilEntered()
        #expect(model.form.busy && model.form.pending == .sendResetLink)
        model.editEmail("changed@example.com")
        await model.submit()
        #expect(model.email == "unknown@example.com" && model.sentEmail == nil)
        await gate.release()
        await attempt.value
        #expect(await gate.entries == 1)
        #expect(model.sentEmail == "unknown@example.com" && !model.form.busy)
    }

    @Test(arguments: [false, true]) func cancellationAndBackIgnoreLateCompletion(back: Bool) async {
        let gate = ForgotRequestGate()
        let source = MockDataSource(delay: { 1 }, sleep: { _ in await gate.wait() })
        let navigation = AuthNavigation()
        navigation.forgot(email: "expired@example.com")
        let model = ForgotPasswordModel(source: source, navigation: navigation, email: navigation.forgotEmail)
        let attempt = Task { await model.submit() }
        await gate.waitUntilEntered()
        if back { model.backToSignIn() } else { attempt.cancel() }
        await gate.release()
        await attempt.value
        #expect(model.sentEmail == nil && model.form.failure == nil && !model.form.busy)
        if back { #expect(navigation.path.isEmpty && navigation.forgotEmail.isEmpty) }
    }

    @Test func emailAppMissingHandlerPreservesTheSentNoticeAndBackReturnsToSignIn() async throws {
        let navigation = AuthNavigation()
        navigation.forgot()
        let model = ForgotPasswordModel(
            source: try authTestSource(), navigation: navigation, email: "unknown@example.com")
        var opened: [URL] = []
        await model.openEmail {
            opened.append($0)
            return false
        }
        #expect(opened.isEmpty)
        await model.submit()
        await model.openEmail {
            opened.append($0)
            return false
        }
        #expect(opened.map(\.absoluteString) == ["message://"])
        #expect(model.sentEmail == "unknown@example.com" && model.form.failure == nil)
        model.backToSignIn()
        #expect(navigation.path.isEmpty)
        await model.openEmail { _ in
            Issue.record("Closed form opened mail")
            return true
        }
    }

    @Test func expiredResetCanPrefillANewFormWithoutReusingSentState() async throws {
        let signIn = SignInModel(
            source: try authTestSource(), session: AuthTestSession(), deviceIdentity: { "test" }, deviceName: "test",
            route: { _ in })
        signIn.navigation.forgot(email: "expired+tag@example.com")
        let model = signIn.makeForgotPasswordModel()
        #expect(model.email == "expired+tag@example.com" && model.sentEmail == nil)
        await model.submit()
        model.backToSignIn()
        signIn.navigation.forgot()
        let fresh = signIn.makeForgotPasswordModel()
        #expect(fresh.email.isEmpty && fresh.sentEmail == nil && fresh.form.failure == nil)
    }

    @Test func noticeUsesTypedInterpolationInEnglishAndDutch() {
        let email = "person+100%@example.com"
        #expect(
            AuthCopy.resetSent(email: email, locale: Locale(identifier: "en"))
                == "If \(email) has an account, a link to choose a new password is on its way.")
        #expect(
            AuthCopy.resetSent(email: email, locale: Locale(identifier: "nl"))
                == "Als er een account bestaat voor \(email), is er een link onderweg om een nieuw wachtwoord te kiezen."
        )
    }
}

actor ForgotRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var entry: CheckedContinuation<Void, Never>?
    private(set) var entries = 0
    func wait() async {
        entries += 1
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

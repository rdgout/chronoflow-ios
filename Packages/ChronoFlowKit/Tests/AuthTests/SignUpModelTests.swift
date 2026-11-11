import AppCore
import Auth
import DataAccess
import Foundation
import Testing

@MainActor struct SignUpModelTests {
    @Test func guestSignupRequiresALiveClaimBeforeCreatingAnAccount() async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "test" },
            deviceName: "test", accept: { _ in Issue.record("Expired guest created an account") })
        model.editName("Traveller")
        model.editEmail("new@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        #expect(await model.submit(language: .en, requiresGuestClaim: true) == .guestReviewExpired)
        #expect(model.guestState == .review && model.password.isEmpty && model.confirmation.isEmpty)
        #expect(try await source.inbox().isEmpty)
    }

    @Test func guestSignupDistinguishesARequestFailureFromAnAccountAwaitingAcceptance() async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(),
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in throw SessionFailure.credentialWrite })
        #expect(model.guestState == .ready)
        model.editName("Traveller")
        model.editEmail("new@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await source.failNext(method: .signUp, error: .server(status: 503))
        await model.submit(language: .en)
        #expect(model.guestState == .failed)
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.guestState == .retry && model.sessionFailure == .credentialWrite)
        #expect(model.password.isEmpty && model.confirmation.isEmpty)
    }

    @Test func expiredGuestClaimShowsReviewAndClearsPasswords() async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "test" },
            deviceName: "test",
            claim: {
                GuestClaim(draftToken: "trip", inputRevision: 1, reviewRevision: 1, guestSecret: "secret")
            }, accept: { _ in Issue.record("Expired claim accepted") })
        await source.failNext(method: .signUp, error: .reviewExpired)
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        #expect(await model.submit(language: .en, requiresGuestClaim: true) == .guestReviewExpired)
        #expect(model.guestState == .review && model.password.isEmpty && model.confirmation.isEmpty)
    }

    @Test(arguments: ["name", "email", "password", "password_confirmation"])
    func unchangedFieldCallbacksPreserveMixedFailureUntilAnEdit(_ field: String) async throws {
        let model = SignUpModel(
            source: try authTestSource(), navigation: AuthNavigation(), deviceIdentity: { "test" },
            deviceName: "test", accept: { _ in })
        var fields = ["email": FieldMessage(key: "This email address is already in use.")]
        if field != "email" { fields[field] = FieldMessage(key: "Please fill this in.") }
        let failure = DataFailure.validation(fields: fields, status: 422)
        model.form.receive(failure)
        let edit: (String) -> Void =
            switch field {
            case "name": model.editName
            case "email": model.editEmail
            case "password": model.editPassword
            default: model.editConfirmation
            }
        edit("")
        #expect(model.form.failure == failure && model.form.banner == .emailTaken)
        if field != "email" { #expect(model.form.fields[field] != nil) }
        edit("changed")
        #expect(model.form.failure == nil && model.form.banner == nil && model.form.fields[field] == nil)
    }

    @Test func registrationUsesDeviceLanguageAndTheExistingSessionController() async throws {
        let source = try authTestSource()
        let session = AuthTestSession()
        var routes: [Route] = []
        let signIn = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "Test phone", route: { routes.append($0) })
        let model = signIn.makeSignUpModel()
        model.editName("Nieuw")
        model.editEmail("new@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .nl)
        #expect(await session.accepted.count == 1)
        #expect(routes == [.verify])
        #expect(
            model.name == "Nieuw" && model.email == "new@example.com" && model.password.isEmpty
                && model.confirmation.isEmpty)
        #expect(try await source.inbox().count == 1)
        let payload = RegisterInput(
            name: "Nieuw", email: model.email, password: "", passwordConfirmation: "", deviceID: "test",
            deviceName: "Test phone", language: .nl)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(object["language"] as? String == "nl" && object["device_name"] as? String == "Test phone")
        #expect(AuthPolicy.terms.url.absoluteString == "https://chronoflow.net/terms")
        #expect(AuthPolicy.privacy.url.absoluteString == "https://chronoflow.net/privacy")
    }
    @Test func serverAloneValidatesAllFieldsAndTakenEmailUsesTheBanner() async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in Issue.record("Invalid registration accepted") })
        await model.submit(language: .en)
        #expect(model.form.fields["name"]?.key == "Please fill this in.")
        model.editName("Name")
        model.editEmail("bad")
        await model.submit(language: .en)
        #expect(model.form.fields["email"] != nil)
        model.editEmail("demo@example.com")
        await model.submit(language: .en)
        #expect(model.form.banner == .emailTaken)
        model.editEmail("new@example.com")
        for value in ["short", "lowercase123456!", "NoNumbersInThis!", "NoSymbols123456"] {
            let model = SignUpModel(
                source: try authTestSource(), navigation: AuthNavigation(),
                deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test",
                accept: { _ in Issue.record("Weak password accepted") })
            model.editName("Name")
            model.editEmail("new@example.com")
            model.editPassword(value)
            model.editConfirmation(value)
            await model.submit(language: .en)
            #expect(model.form.fields["password"] != nil && model.password.isEmpty && model.confirmation.isEmpty)
        }
    }
    @Test(arguments: [false, true])
    func uiTestSeedReturnsTheExpectedRegistrationBanner(offline: Bool) async throws {
        let source = MockDataSource(
            seed: try MockAppSeed.make(now: Date()), offline: offline, delay: { 0 }, sleep: { _ in })
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in Issue.record("Failed registration accepted") })
        let email = offline ? "new@example.com" : "demo@example.com"
        model.editName("Traveller")
        model.editEmail(email)
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.form.banner == (offline ? .offline : .emailTaken))
        #expect(model.form.fields.isEmpty)
        #expect(model.name == "Traveller" && model.email == email)
        #expect(model.password.isEmpty && model.confirmation.isEmpty && !model.form.busy)
    }

    @Test func failuresPreserveNameEmailAndClearPasswordsIncludingKeychainFailure() async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in throw SessionFailure.credentialWrite })
        model.editName("Name")
        model.editEmail("new@example.com")
        for failure in [
            DataFailure.offline, .server(status: 500), .throttled(retryAfterSeconds: 60, status: 429),
            .validation(
                fields: ["password_confirmation": FieldMessage(key: "The passwords don't match yet.")], status: 422),
        ] {
            await source.failNext(method: .signUp, error: failure)
            model.editPassword("NewPassword123!")
            model.editConfirmation("NewPassword123!")
            await model.submit(language: .en)
            #expect(model.form.failure == failure && model.password.isEmpty && model.confirmation.isEmpty)
            #expect(model.name == "Name" && model.email == "new@example.com")
        }
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.sessionFailure == .credentialWrite && model.password.isEmpty && model.confirmation.isEmpty)
        #expect(model.form.banner == .server && model.form.takeAnnouncement(locale: Locale(identifier: "nl")) != nil)
    }

    @Test(arguments: [
        SessionFailure.credentialsUnavailable, .databaseUnavailable, .credentialWrite, .invalidResult, .superseded,
    ])
    func createdAccountAfterSessionFailureCanRecoverThroughSignIn(_ failure: SessionFailure) async throws {
        let source = try authTestSource()
        let session = AuthTestSession()
        await session.fail(failure)
        var routes: [Route] = []
        let signIn = SignInModel(
            source: source, session: session, deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", route: { routes.append($0) })
        signIn.navigation.push(.signUp)
        let model = signIn.makeSignUpModel()
        model.editName("Name")
        model.editEmail("new@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.sessionFailure == failure && model.form.banner == .server)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "en")) != nil)
        #expect(routes.isEmpty && signIn.navigation.path == [.signUp])
        #expect(model.password.isEmpty && model.confirmation.isEmpty)
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.sessionFailure == nil && model.form.banner == .emailTaken)
        #expect(model.form.takeAnnouncement(locale: Locale(identifier: "nl")) != nil)
        #expect(model.name == "Name" && model.email == "new@example.com")
        #expect(model.password.isEmpty && model.confirmation.isEmpty)
        #expect(try await source.inbox().count == 1)
        model.backToSignIn()
        #expect(signIn.navigation.path.isEmpty)
        await session.fail(nil)
        signIn.editEmail(model.email)
        signIn.editPassword("NewPassword123!")
        await signIn.submitPassword()
        #expect(await session.accepted.count == 1)
        #expect(signIn.form.failure == nil && signIn.sessionFailure == nil && routes == [.verify])
    }
    @Test(arguments: [
        "Use at least one symbol.", "The passwords don't match yet.",
        "This password has appeared in a data leak. Choose a different password.",
    ])
    func emailTakenPreservesOtherFieldErrorsInTheSameResponse(passwordMessage: String) async throws {
        let source = try authTestSource()
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in Issue.record("Invalid registration accepted") })
        let field = passwordMessage == "The passwords don't match yet." ? "password_confirmation" : "password"
        let remaining = [
            "name": FieldMessage(key: "Please fill this in."), field: FieldMessage(key: passwordMessage),
        ]
        await source.failNext(
            method: .signUp,
            error: .validation(
                fields: remaining.merging(["email": FieldMessage(key: "This email address is already in use.")]) {
                    first, _ in first
                }, status: 422))
        model.editEmail("demo@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit(language: .en)
        #expect(model.form.banner == .emailTaken)
        #expect(model.form.fields == remaining)
        #expect(model.password.isEmpty && model.confirmation.isEmpty)
        #expect(model.email == "demo@example.com")
    }

    @Test func unchangedConfirmationPreservesServerFeedbackUntilTheValueChanges() throws {
        let model = SignUpModel(
            source: try authTestSource(), navigation: AuthNavigation(),
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test", accept: { _ in })
        let mismatch = FieldMessage(key: "The passwords don't match yet.")
        let failure = DataFailure.validation(
            fields: [
                "email": FieldMessage(key: "This email address is already in use."),
                "password_confirmation": mismatch,
            ], status: 422)
        model.form.receive(failure)

        model.editConfirmation(model.confirmation)
        #expect(model.form.banner == .emailTaken)
        #expect(model.form.fields["password_confirmation"] == mismatch)
        #expect(model.form.failure == failure)

        model.editConfirmation("NewPassword123!")
        #expect(model.form.banner == nil)
        #expect(model.form.fields["password_confirmation"] == nil)
        #expect(model.form.failure == nil)
    }

    @Test func emailTakenKeepsBannerWhenOtherMessagesNeedTheFallback() {
        let mapped = AuthFailureMapping(
            .validation(
                fields: [
                    "email": FieldMessage(key: "This email address is already in use."),
                    "password": FieldMessage(key: "unknown English"),
                    "device_id": FieldMessage(key: "Please fill this in."),
                    "name": FieldMessage(key: "Please fill this in."),
                ], status: 422),
            displayedFields: ["name", "email", "password", "password_confirmation"], context: .signUp)
        #expect(mapped.banner == .emailTaken)
        #expect(mapped.fields == ["name": FieldMessage(key: "Please fill this in.")])
    }
    @Test func oneToggleControlsBothPasswordsAndBusyCancellationStopsAcceptance() async {
        let gate = ForgotRequestGate()
        let source = MockDataSource(delay: { 1 }, sleep: { _ in await gate.wait() })
        let model = SignUpModel(
            source: source, navigation: AuthNavigation(), deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" },
            deviceName: "test", accept: { _ in Issue.record("Canceled registration accepted") })
        model.editName("Name")
        model.editEmail("new@example.com")
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        model.togglePassword()
        #expect(model.showsPassword)
        let task = Task { await model.submit(language: .en) }
        await gate.waitUntilEntered()
        await model.submit(language: .en)
        model.editName("ignored")
        model.togglePassword()
        #expect(model.name == "Name" && model.showsPassword)
        model.cancel()
        task.cancel()
        await gate.release()
        await task.value
        #expect(await gate.entries == 1)
        #expect(model.password.isEmpty && model.confirmation.isEmpty && !model.showsPassword)
    }
}

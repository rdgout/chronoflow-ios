import AppCore
import Foundation
import Observation

@MainActor @Observable public final class SignInModel {
    public private(set) var email = ""
    public private(set) var password = ""
    public let form: AuthFormModel
    public let navigation: AuthNavigation
    public private(set) var twoFactor: TwoFactorModel?
    private let source: any DataSource
    private let session: any SessionControlling
    private let deviceIdentity: @Sendable () async throws -> String
    private let deviceName: String
    private let claim: @Sendable () async -> GuestClaim?
    private let guestReviewExpired: @Sendable (GuestClaim) async -> Void
    private let accepted: @MainActor (SessionResult, AuthenticationMethod) async throws -> Void
    private let passkey: PasskeySignIn
    public var mockMail: (@MainActor (String) async -> AuthLink?)?
    public private(set) var sessionFailure: SessionFailure?

    public init(
        source: any DataSource, session: any SessionControlling,
        deviceIdentity: @escaping @Sendable () async throws -> String, deviceName: String,
        assertionProvider: any PasskeyAssertionProviding = DeterministicAssertionProvider(),
        claim: @escaping @Sendable () async -> GuestClaim? = { nil },
        guestReviewExpired: @escaping @Sendable (GuestClaim) async -> Void = { _ in },
        accepted: @escaping @MainActor (SessionResult, AuthenticationMethod) async throws -> Void
    ) {
        self.source = source
        self.session = session
        self.deviceIdentity = deviceIdentity
        self.deviceName = deviceName
        self.claim = claim
        self.guestReviewExpired = guestReviewExpired
        self.passkey = PasskeySignIn(
            source: source, provider: assertionProvider, identity: deviceIdentity, deviceName: deviceName, claim: claim)
        self.accepted = accepted
        form = AuthFormModel()
        navigation = AuthNavigation()
    }
    public convenience init(
        source: any DataSource, session: any SessionControlling,
        deviceIdentity: @escaping @Sendable () async throws -> String, deviceName: String,
        assertionProvider: any PasskeyAssertionProviding = DeterministicAssertionProvider(),
        claim: @escaping @Sendable () async -> GuestClaim? = { nil },
        guestReviewExpired: @escaping @Sendable (GuestClaim) async -> Void = { _ in },
        route: @escaping @MainActor (Route) async -> Void
    ) {
        self.init(
            source: source, session: session, deviceIdentity: deviceIdentity, deviceName: deviceName,
            assertionProvider: assertionProvider, claim: claim, guestReviewExpired: guestReviewExpired,
            accepted: { result, _ in await route(AuthNavigation.route(for: result.account)) })
    }

    public func editEmail(_ value: String) {
        guard !form.busy, value != email else { return }
        email = value
        form.edit("email")
    }
    public func makeForgotPasswordModel() -> ForgotPasswordModel {
        ForgotPasswordModel(source: source, navigation: navigation, email: navigation.forgotEmail, mail: mailAction)
    }
    private var mailAction: (@MainActor (String) async -> Bool)? {
        guard mockMail != nil else { return nil }
        return { [weak self] email in
            guard let self, let link = await mockMail?(email) else { return false }
            if case .reset(let input) = link { openReset(input) }
            return true
        }
    }
    public func makeSignUpModel() -> SignUpModel {
        SignUpModel(
            source: source, navigation: navigation, deviceIdentity: deviceIdentity, deviceName: deviceName,
            claim: claim, guestReviewExpired: guestReviewExpired
        ) {
            [weak self] result in
            guard let self else { throw CancellationError() }
            try await self.accept(result, method: .signUp)
        }
    }
    public func openReset(_ link: ResetPasswordLink) {
        password = ""
        twoFactor?.cancel()
        twoFactor = nil
        navigation.reset()
        navigation.push(.reset(link))
    }
    public func makeResetPasswordModel(_ link: ResetPasswordLink) -> ResetPasswordModel {
        ResetPasswordModel(link: link, source: source, navigation: navigation, mail: mailAction)
    }
    public func editPassword(_ value: String) {
        guard !form.busy, value != password else { return }
        password = value
        form.edit("password")
    }
    public func submitPassword() async {
        guard form.begin(.password) else { return }
        sessionFailure = nil
        defer {
            password = ""
            form.finish()
        }
        do {
            let id = try await deviceIdentity()
            let claim = await claim()
            try Task.checkCancellation()
            let result = try await source.signIn(
                PasswordSignInInput(
                    email: email, password: password, deviceID: id, deviceName: deviceName,
                    draftToken: claim?.draftToken, guestSecret: claim?.guestSecret))
            try Task.checkCancellation()
            switch result {
            case .session(let result): try await accept(result, method: .password)
            case .twoFactor(let challenge):
                navigation.twoFactor(challengeID: challenge)
                twoFactor = TwoFactorModel(source: source, navigation: navigation) { [weak self] result in
                    guard let self else { throw CancellationError() }
                    try await self.accept(result, method: .twoFactor)
                }
            }
        } catch { receive(error) }
    }
    public func submitPasskey() async {
        guard form.begin(.passkey) else { return }
        sessionFailure = nil
        defer {
            password = ""
            form.finish()
        }
        do {
            let result = try await passkey.signIn()
            try await accept(result, method: .passkey)
        } catch { receive(error) }
    }
    private func accept(_ result: SessionResult, method: AuthenticationMethod) async throws {
        try Task.checkCancellation()
        try await session.accept(result)
        password = ""
        try await accepted(result, method)
    }
    private func receive(_ error: any Error) {
        guard !(error is CancellationError), error as? PasskeyFailure != .canceled else { return }
        if let failure = error as? SessionFailure {
            sessionFailure = failure
        }
        form.receive(error as? DataFailure ?? .server(status: nil))
    }
    public func clearPassword() { password = "" }
    public func clearSecrets() {
        password = ""
        twoFactor?.cancel()
        twoFactor = nil
        navigation.reset()
        form.clear()
    }
}

import AppCore
import Foundation
import Observation

@MainActor @Observable public final class SignInModel {
    public private(set) var email = ""
    public private(set) var password = ""
    public let form: AuthFormModel
    public let navigation: AuthNavigation
    private let source: any DataSource
    private let session: any SessionControlling
    private let deviceIdentity: @Sendable () async throws -> String
    private let deviceName: String
    private let route: @MainActor (Route) async -> Void
    private let passkey: PasskeySignIn
    public private(set) var sessionFailure: SessionFailure?

    public init(
        source: any DataSource, session: any SessionControlling,
        deviceIdentity: @escaping @Sendable () async throws -> String, deviceName: String,
        assertionProvider: any PasskeyAssertionProviding = DeterministicAssertionProvider(),
        route: @escaping @MainActor (Route) async -> Void
    ) {
        self.source = source
        self.session = session
        self.deviceIdentity = deviceIdentity
        self.deviceName = deviceName
        self.passkey = PasskeySignIn(
            source: source, provider: assertionProvider, identity: deviceIdentity, deviceName: deviceName)
        self.route = route
        form = AuthFormModel()
        navigation = AuthNavigation()
    }
    public func editEmail(_ value: String) {
        guard !form.busy else { return }
        email = value
        form.edit("email")
    }
    public func editPassword(_ value: String) {
        guard !form.busy else { return }
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
            try Task.checkCancellation()
            let result = try await source.signIn(
                PasswordSignInInput(email: email, password: password, deviceID: id, deviceName: deviceName))
            try Task.checkCancellation()
            switch result {
            case .session(let result): try await accept(result)
            case .twoFactor(let challenge): navigation.twoFactor(challengeID: challenge)
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
            try await accept(result)
        } catch { receive(error) }
    }
    private func accept(_ result: SessionResult) async throws {
        try Task.checkCancellation()
        try await session.accept(result)
        password = ""
        await route(AuthNavigation.route(for: result.account))
    }
    private func receive(_ error: any Error) {
        guard !(error is CancellationError), error as? PasskeyFailure != .canceled else { return }
        // Storage errors have no board and remain a typed service seam without a designed presentation.
        if let failure = error as? SessionFailure {
            sessionFailure = failure
            return
        }
        form.receive(error as? DataFailure ?? .server(status: nil))
    }
    public func clearPassword() { password = "" }
    public func clearSecrets() {
        password = ""
        navigation.reset()
        form.clear()
    }
}

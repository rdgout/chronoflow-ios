import AppCore
import Foundation
import Observation

@MainActor @Observable public final class SignUpModel {
    public private(set) var name = ""
    public private(set) var email = ""
    public private(set) var password = ""
    public private(set) var confirmation = ""
    public private(set) var showsPassword = false
    public private(set) var sessionFailure: SessionFailure?
    public let form = AuthFormModel(
        displayedFields: ["name", "email", "password", "password_confirmation"], context: .signUp)
    private let source: any DataSource
    private let deviceIdentity: @Sendable () async throws -> String
    private let deviceName: String
    private let accept: @MainActor (SessionResult) async throws -> Void
    private let navigation: AuthNavigation
    private var active = true

    public init(
        source: any DataSource, navigation: AuthNavigation,
        deviceIdentity: @escaping @Sendable () async throws -> String, deviceName: String,
        accept: @escaping @MainActor (SessionResult) async throws -> Void
    ) {
        self.source = source
        self.navigation = navigation
        self.deviceIdentity = deviceIdentity
        self.deviceName = deviceName
        self.accept = accept
    }
    public func editName(_ value: String) {
        guard active, !form.busy, value != name else { return }
        name = value
        form.edit("name")
    }
    public func editEmail(_ value: String) {
        guard active, !form.busy, value != email else { return }
        email = value
        form.edit("email")
    }
    public func editPassword(_ value: String) {
        guard active, !form.busy, value != password else { return }
        password = value
        form.edit("password")
    }
    public func editConfirmation(_ value: String) {
        guard active, !form.busy, value != confirmation else { return }
        confirmation = value
        form.edit("password_confirmation")
    }
    public func togglePassword() {
        guard active, !form.busy else { return }
        showsPassword.toggle()
    }
    public func submit(language: AuthLanguage) async {
        guard active, form.begin(.register) else { return }
        sessionFailure = nil
        defer {
            clearPasswords()
            form.finish()
        }
        do {
            let id = try await deviceIdentity()
            try Task.checkCancellation()
            guard active else { return }
            let result = try await source.signUp(
                RegisterInput(
                    name: name, email: email, password: password,
                    passwordConfirmation: confirmation, deviceID: id, deviceName: deviceName, language: language))
            try Task.checkCancellation()
            guard active else { return }
            try await accept(result)
        } catch {
            guard active, !Task.isCancelled, !(error is CancellationError) else { return }
            if let failure = error as? SessionFailure {
                sessionFailure = failure
            }
            form.receive(error as? DataFailure ?? .server(status: nil))
        }
    }
    public func clearPasswords() {
        password = ""
        confirmation = ""
    }
    public func backToSignIn() {
        cancel()
        navigation.reset()
    }
    public func cancel() {
        active = false
        clearPasswords()
        showsPassword = false
        form.clear()
    }
}

nonisolated public enum AuthPolicy: String, Sendable {
    case terms, privacy
    public var url: URL { URL(string: "https://chronoflow.net/" + rawValue)! }
}

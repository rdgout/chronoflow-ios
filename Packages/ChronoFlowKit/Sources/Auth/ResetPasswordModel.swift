import AppCore
import Foundation
import Observation

@MainActor @Observable public final class ResetPasswordModel {
    public enum State: Sendable { case form, expired, done }
    public private(set) var state: State
    public private(set) var password = ""
    public private(set) var confirmation = ""
    public let link: ResetPasswordLink
    public let form = AuthFormModel(displayedFields: ["password", "password_confirmation"], context: .reset)
    public let recovery: ForgotPasswordModel
    private let source: any DataSource
    private let navigation: AuthNavigation
    private var active = true

    public init(
        link: ResetPasswordLink, source: any DataSource, navigation: AuthNavigation,
        mail: (@MainActor (String) async -> Bool)? = nil
    ) {
        self.link = link
        self.source = source
        self.navigation = navigation
        state = link.isValid ? .form : .expired
        recovery = ForgotPasswordModel(source: source, navigation: navigation, email: link.email, mail: mail)
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
    public func submit() async {
        guard active, state == .form, form.begin(.reset) else { return }
        defer {
            clearPasswords()
            form.finish()
        }
        do {
            try Task.checkCancellation()
            try await source.resetPassword(
                ResetPasswordInput(
                    token: link.token, email: link.email, password: password, passwordConfirmation: confirmation))
            try Task.checkCancellation()
            guard active else { return }
            state = .done
        } catch {
            guard active, !Task.isCancelled, !(error is CancellationError) else { return }
            if case .validation(let fields, _) = error as? DataFailure,
                fields.values.contains(where: { $0.key == "This password reset link is invalid or has expired." })
            {
                state = .expired
            } else {
                form.receive(error as? DataFailure ?? .server(status: nil))
            }
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
        form.clear()
        recovery.cancel()
    }
}

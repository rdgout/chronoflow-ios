import AppCore
import Foundation
import Observation

@MainActor @Observable public final class ForgotPasswordModel {
    public private(set) var email: String
    public private(set) var sentEmail: String?
    public let form = AuthFormModel(displayedFields: ["email"], context: .forgot)
    private let source: any DataSource
    private let navigation: AuthNavigation
    private var active = true
    private let mail: (@MainActor () async -> Bool)?

    public init(
        source: any DataSource, navigation: AuthNavigation, email: String = "",
        mail: (@MainActor () async -> Bool)? = nil
    ) {
        self.source = source
        self.navigation = navigation
        self.email = email
        self.mail = mail
    }

    public func editEmail(_ value: String) {
        guard active, !form.busy, value != email else { return }
        email = value
        form.edit("email")
    }

    public func submit() async {
        guard active, sentEmail == nil, form.begin(.sendResetLink) else { return }
        let submittedEmail = email
        defer { form.finish() }
        do {
            try Task.checkCancellation()
            try await source.requestPasswordReset(email: submittedEmail)
            try Task.checkCancellation()
            guard active else { return }
            sentEmail = submittedEmail
        } catch {
            guard active, !Task.isCancelled, !(error is CancellationError) else { return }
            form.receive(error as? DataFailure ?? .server(status: nil))
        }
    }

    public func openEmail(using open: @MainActor (URL) async -> Bool) async {
        guard active, sentEmail != nil, let url = URL(string: "message://") else { return }
        if let mail { _ = await mail() } else { _ = await open(url) }
    }

    public func backToSignIn() {
        cancel()
        navigation.reset()
    }

    public func cancel() {
        active = false
        form.clear()
    }
}

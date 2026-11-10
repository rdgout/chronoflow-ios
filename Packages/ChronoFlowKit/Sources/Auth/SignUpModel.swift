import AppCore
import DataAccess
import Foundation
import Observation

@MainActor @Observable public final class SignUpModel {
    public enum Outcome: Sendable, Equatable { case accepted, guestReviewExpired }
    public private(set) var name = ""
    public private(set) var email = ""
    public private(set) var password = ""
    public private(set) var confirmation = ""
    public private(set) var showsPassword = false
    public private(set) var sessionFailure: SessionFailure?
    public private(set) var guestState: GuestSignupState = .ready
    public let form = AuthFormModel(
        displayedFields: ["name", "email", "password", "password_confirmation"], context: .signUp)
    private let source: any DataSource
    private let deviceIdentity: @Sendable () async throws -> String
    private let deviceName: String
    private let claim: @Sendable () async -> GuestClaim?
    private let guestReviewExpired: @Sendable (GuestClaim) async -> Void
    private let accept: @MainActor (SessionResult) async throws -> Void
    private let navigation: AuthNavigation
    private var active = true

    public init(
        source: any DataSource, navigation: AuthNavigation,
        deviceIdentity: @escaping @Sendable () async throws -> String, deviceName: String,
        claim: @escaping @Sendable () async -> GuestClaim? = { nil },
        guestReviewExpired: @escaping @Sendable (GuestClaim) async -> Void = { _ in },
        accept: @escaping @MainActor (SessionResult) async throws -> Void
    ) {
        self.source = source
        self.navigation = navigation
        self.deviceIdentity = deviceIdentity
        self.deviceName = deviceName
        self.claim = claim
        self.guestReviewExpired = guestReviewExpired
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
    @discardableResult public func submit(language: AuthLanguage, requiresGuestClaim: Bool = false) async -> Outcome? {
        guard active, form.begin(.register) else { return nil }
        sessionFailure = nil
        guestState = .ready
        defer {
            clearPasswords()
            form.finish()
        }
        var attemptedClaim: GuestClaim?
        var accountCreated = false
        do {
            let id = try await deviceIdentity()
            let claim = await claim()
            guard !requiresGuestClaim || claim != nil else {
                guestState = .review
                return .guestReviewExpired
            }
            attemptedClaim = claim
            try Task.checkCancellation()
            guard active else { return nil }
            let result = try await source.signUp(
                RegisterInput(
                    name: name, email: email, password: password,
                    passwordConfirmation: confirmation, deviceID: id, deviceName: deviceName, language: language,
                    draftToken: claim?.draftToken, inputRevision: claim?.inputRevision,
                    reviewRevision: claim?.reviewRevision, guestSecret: claim?.guestSecret))
            try Task.checkCancellation()
            guard active else { return nil }
            accountCreated = true
            try await accept(result)
            return .accepted
        } catch {
            guard active, !Task.isCancelled, !(error is CancellationError) else { return nil }
            if let attemptedClaim, let failure = error as? DataFailure,
                TripWizardErrors.map(failure) == .reviewExpired
            {
                await guestReviewExpired(attemptedClaim)
                guestState = .review
                return .guestReviewExpired
            }
            if let failure = error as? SessionFailure {
                sessionFailure = failure
            }
            form.receive(error as? DataFailure ?? .server(status: nil))
            guestState = accountCreated ? .retry : form.banner == nil ? .ready : .failed
            return nil
        }
    }
    public func clearPasswords() {
        password = ""
        confirmation = ""
    }
    #if DEBUG
        public func seedGuestSignupState(_ state: GuestSignupState) {
            guestState = state
        }
    #endif
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

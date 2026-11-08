import AppCore
import Foundation
import Observation

nonisolated public enum AuthBannerKind: String, CaseIterable, Sendable {
    case credentials, locked, server, emailTaken, offline
    public var title: String {
        switch self {
        case .emailTaken: "There's already an account with this email."
        case .credentials: "That email and password don't match."
        case .locked: "Too many attempts."
        case .server: "Something went wrong on our side."
        case .offline: "Needs a connection"
        }
    }
    public var body: String {
        switch self {
        case .emailTaken: "Sign in instead, or reset your password."
        case .credentials: "Check both and try again, or reset your password."
        case .locked: "Wait a few minutes before you try again, or reset your password now."
        case .server: "Try again in a moment."
        case .offline: ""
        }
    }
    public func body(for context: AuthFormContext) -> String {
        if self == .server && context == .verify { return "We couldn't send the link. Try again in a moment." }
        if self == .server && context == .signUp { return "Your details are kept. Try again in a moment." }
        if self == .server && context == .reset { return "Your new password wasn't saved. Try again in a moment." }
        if self == .locked && context == .forgot { return "Wait a few minutes before you ask for another link." }
        if self == .locked && (context == .twoFactor || context == .reset || context == .signUp || context == .verify) {
            return "Wait a few minutes before you try again."
        }
        return body
    }
    public func title(for context: AuthFormContext) -> String {
        if self == .locked && context == .forgot { return "Too many requests." }
        return title
    }
}

nonisolated public enum AuthFormContext: Sendable { case signIn, twoFactor, forgot, reset, signUp, verify }

nonisolated public struct AuthFailureMapping: Sendable, Equatable {
    public var banner: AuthBannerKind?
    public var fields: [String: FieldMessage] = [:]
    public var retryAfterSeconds: TimeInterval?

    public init(_ failure: DataFailure, displayedFields: Set<String>, context: AuthFormContext = .signIn) {
        switch failure {
        case .offline: banner = .offline
        case .throttled(let seconds, _):
            banner = .locked
            retryAfterSeconds = seconds
        case .validation(let messages, _):
            if context == .signUp, messages["email"]?.key == "This email address is already in use." {
                banner = .emailTaken
            }
            if context == .signIn
                && messages.values.contains(where: {
                    $0.key == "These sign-in details don't match our records."
                })
            {
                banner = .credentials
                return
            }
            let proofFields: Set<String> = ["code", "recovery_code"]
            let activeProofHasError =
                context == .twoFactor
                && !displayedFields.intersection(proofFields).isDisjoint(with: messages.keys)
            for (name, message) in messages {
                if banner == .emailTaken && name == "email" { continue }
                if activeProofHasError && proofFields.contains(name) && !displayedFields.contains(name) { continue }
                if displayedFields.contains(name), AuthCopy.supports(message) {
                    if context == .twoFactor && name == "code"
                        && message.key == "The authentication code was not accepted. Try again."
                    {
                        fields[name] = FieldMessage(
                            key: "That code didn't work. Codes change every 30 seconds, so try the newest one.")
                    } else {
                        fields[name] = message
                    }
                } else if banner == nil {
                    banner = .server
                }
            }
        default: banner = .server
        }
        if banner == nil && fields.isEmpty { banner = .server }
    }
}

@MainActor @Observable public final class AuthFormModel {
    public enum Action: Sendable {
        case password, passkey, verify, sendResetLink, reset, register, checkVerification, resendVerification, signOut
    }
    public private(set) var pending: Action?
    public private(set) var banner: AuthBannerKind?
    public private(set) var fields: [String: FieldMessage] = [:]
    public private(set) var failure: DataFailure?
    public private(set) var retryAfterSeconds: TimeInterval?
    public private(set) var announcementRevision = 0
    private var announcedRevision = 0
    private var displayedFields: Set<String>
    public let context: AuthFormContext
    public var busy: Bool { pending != nil }

    public init(displayedFields: Set<String> = ["email", "password"], context: AuthFormContext = .signIn) {
        self.displayedFields = displayedFields
        self.context = context
    }

    public func showFields(_ fields: Set<String>) {
        guard !busy else { return }
        displayedFields = fields
        clear()
    }

    public func begin(_ action: Action) -> Bool {
        guard !busy else { return false }
        pending = action
        clear()
        return true
    }
    public func finish() { pending = nil }
    public func edit(_ field: String) {
        guard !busy else { return }
        banner = nil
        failure = nil
        fields.removeValue(forKey: field)
    }
    public func clear() {
        banner = nil
        fields = [:]
        failure = nil
        retryAfterSeconds = nil
    }
    public func receive(_ failure: DataFailure) {
        self.failure = failure
        let mapped = AuthFailureMapping(failure, displayedFields: displayedFields, context: context)
        banner = mapped.banner
        fields = mapped.fields
        retryAfterSeconds = mapped.retryAfterSeconds
        announcementRevision += 1
    }
    public func takeAnnouncement(locale: Locale) -> String? {
        guard announcedRevision != announcementRevision else { return nil }
        var messages: [String] = []
        if let banner {
            messages.append(AuthCopy.string(banner.title(for: context), locale: locale))
            let body = banner.body(for: context)
            if !body.isEmpty { messages.append(AuthCopy.string(body, locale: locale)) }
        }
        messages += fields.keys.sorted().compactMap { fields[$0].flatMap { AuthCopy.field($0, locale: locale) } }
        guard !messages.isEmpty else { return nil }
        announcedRevision = announcementRevision
        return messages.joined(separator: " ")
    }
}

import AppCore
import Foundation
import Observation

nonisolated public enum AuthBannerKind: String, CaseIterable, Sendable {
    case credentials, locked, server
    public var title: String {
        switch self {
        case .credentials: "That email and password don't match."
        case .locked: "Too many attempts."
        case .server: "Something went wrong on our side."
        }
    }
    public var body: String {
        switch self {
        case .credentials: "Check both and try again, or reset your password."
        case .locked: "Wait a few minutes before you try again, or reset your password now."
        case .server: "Try again in a moment."
        }
    }
    public func body(for context: AuthFormContext) -> String {
        if self == .locked && context == .twoFactor { return "Wait a few minutes before you try again." }
        return body
    }
}

nonisolated public enum AuthFormContext: Sendable { case signIn, twoFactor }

nonisolated public struct AuthFailureMapping: Sendable, Equatable {
    public var banner: AuthBannerKind?
    public var fields: [String: FieldMessage] = [:]
    public var retryAfterSeconds: TimeInterval?

    public init(_ failure: DataFailure, displayedFields: Set<String>, context: AuthFormContext = .signIn) {
        switch failure {
        case .offline: break
        case .throttled(let seconds, _):
            banner = .locked
            retryAfterSeconds = seconds
        case .validation(let messages, _):
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
                } else {
                    banner = .server
                }
            }
        default: banner = .server
        }
    }
}

@MainActor @Observable public final class AuthFormModel {
    public enum Action: Sendable { case password, passkey, verify }
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
        if banner != nil { announcementRevision += 1 }
    }
    public func takeAnnouncement(locale: Locale) -> String? {
        guard let banner, announcedRevision != announcementRevision else { return nil }
        announcedRevision = announcementRevision
        return AuthCopy.string(banner.title, locale: locale) + " "
            + AuthCopy.string(banner.body(for: context), locale: locale)
    }
}

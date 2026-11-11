import AppCore
import Foundation
import Observation

public enum SettingsSecurityPrompt: String, Identifiable, Sendable {
    case enable, disable, reveal, regenerate
    public var id: String { rawValue }
    public var detail: String {
        switch self {
        case .enable: "Enter your password to turn on two-factor authentication."
        case .disable: "Enter your password to turn off two-factor authentication."
        case .reveal: "Enter your password to show your recovery codes."
        case .regenerate: "Enter your password to make new recovery codes. Your current codes stop working."
        }
    }
    public var button: String {
        switch self {
        case .enable: "Continue"
        case .disable: "Turn off"
        case .reveal: "Show codes"
        case .regenerate: "Make new codes"
        }
    }
    public func change(password: String) -> AccountSecurityChange {
        switch self {
        case .enable: .enableTwoFactor(current: password)
        case .disable: .disableTwoFactor(current: password)
        case .reveal: .revealRecoveryCodes(current: password)
        case .regenerate: .regenerateRecoveryCodes(current: password)
        }
    }
}

@MainActor @Observable public final class SettingsSecurityModel {
    public var currentPassword = ""
    public var newPassword = ""
    public var confirmation = ""
    public var prompt: SettingsSecurityPrompt?
    public var promptPassword = ""
    public var code = ""
    public private(set) var setup: ApiTwoFactorSetup?
    public private(set) var codes: [String] = []
    public private(set) var busy = false
    public private(set) var message: String?
    public var twoFactorActivationFailed: Bool { message == "Couldn't turn on two-factor." }
    public private(set) var errors: [String: String] = [:]
    private var errorArguments: [String: [String: String]] = [:]
    public private(set) var retryAt: Date?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let perform: @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult
    @ObservationIgnored private let now: @Sendable () -> Date
    public init(
        perform: @escaping @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.perform = perform
        self.now = now
    }
    public func refreshLock() {
        if let retryAt, retryAt <= now() { self.retryAt = nil }
    }
    public func errorText(_ field: String, language: Language) -> String? {
        errors[field].map { SettingsStrings.text($0, language: language, errorArguments[field] ?? [:]) }
    }
    public var locked: Bool { retryAt.map { $0 > now() } ?? false }
    public func remaining(at date: Date) -> Int { max(0, Int(ceil(retryAt?.timeIntervalSince(date) ?? 0))) }

    public func changePassword() async {
        guard !busy, !locked else { return }
        errors = [:]
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            errors["password"] = "Enter your password."
            return
        }
        guard newPassword == confirmation else {
            errors["password_confirmation"] = "The passwords don't match."
            return
        }
        let change = AccountSecurityChange.password(
            current: currentPassword, password: newPassword, confirmation: confirmation)
        currentPassword = ""
        newPassword = ""
        confirmation = ""
        if await run(change) { message = "Password updated" }
    }
    public func showPrompt(_ action: SettingsSecurityPrompt) {
        guard !busy else { return }
        promptPassword = ""
        errors = [:]
        message = nil
        prompt = action
    }
    public func cancelPrompt() {
        guard !busy else { return }
        prompt = nil
        promptPassword = ""
        errors = [:]
        message = nil
    }
    public func submitPrompt() async {
        guard let prompt, !promptPassword.isEmpty, !busy, !locked else { return }
        let password = promptPassword
        promptPassword = ""
        if await run(prompt.change(password: password)) { self.prompt = nil }
    }
    public func confirm() async {
        guard !busy, !locked else { return }
        guard code.count == 6, code.utf8.allSatisfy({ (48...57).contains($0) }) else {
            errors["code"] = "Enter the 6-digit code from your authenticator app."
            return
        }
        let value = code
        code = ""
        if await run(.confirmTwoFactor(code: value)) { message = "Two-factor is on. Save your recovery codes now." }
    }
    @discardableResult private func run(_ change: AccountSecurityChange) async -> Bool {
        let started = generation
        busy = true
        errors = [:]
        message = nil
        defer { if generation == started { busy = false } }
        do {
            let result = try await perform(change)
            guard generation == started, !Task.isCancelled else { return false }
            retryAt = nil
            switch result {
            case .changed: break
            case .setup(let value):
                setup = value
                codes = []
            case .codes(let value):
                codes = value.recoveryCodes
                setup = nil
            case .snapshot:
                setup = nil
                codes = []
            }
            return true
        } catch is CancellationError { return false } catch {
            guard generation == started else { return false }
            switch error as? DataFailure {
            case .offline: message = "Needs a connection."
            case .throttled(let seconds, _):
                retryAt = now().addingTimeInterval(max(0, seconds))
                message = "Too many attempts."
            case .validation(let fields, _):
                for (field, value) in fields {
                    switch value.key {
                    case "The provided password was incorrect.": errors[field] = value.key
                    case "Use at least :min characters.":
                        errors[field] = "Use at least {{min}} characters."
                        if case .number(let min) = value.arguments["min"] {
                            errorArguments[field] = ["min": NSDecimalNumber(decimal: min).stringValue]
                        }
                    case "Use both uppercase and lowercase letters.", "Use at least one number.",
                        "Use at least one symbol.", "The passwords don't match yet.":
                        errors[field] =
                            value.key == "The passwords don't match yet." ? "The passwords don't match." : value.key
                    case "Two-factor authentication is already on.", "Two-factor authentication is off.",
                        "Start two-factor setup again.":
                        message = value.key
                        setup = nil
                        codes = []
                    case "The authentication code was not accepted. Try again.":
                        errors[field] = "That code didn't work. Codes change every 30 seconds; try the newest one."
                    default: errors[field] = "Check the highlighted field."
                    }
                }
                if fields.isEmpty { message = failureMessage(for: change) }
            default: message = failureMessage(for: change)
            }
            return false
        }
    }
    private func failureMessage(for change: AccountSecurityChange) -> String {
        switch change {
        case .enableTwoFactor, .confirmTwoFactor: "Couldn't turn on two-factor."
        default: "Something went wrong"
        }
    }
    public func sendReset(email: String) async {
        guard !busy, !locked else { return }
        if await run(.requestPasswordReset(email: email)) { message = "Check your inbox." }
    }
    public func clearSecrets() {
        generation += 1
        busy = false
        message = nil
        errors = [:]
        errorArguments = [:]
        currentPassword = ""
        newPassword = ""
        confirmation = ""
        promptPassword = ""
        code = ""
        setup = nil
        codes = []
        prompt = nil
    }
}

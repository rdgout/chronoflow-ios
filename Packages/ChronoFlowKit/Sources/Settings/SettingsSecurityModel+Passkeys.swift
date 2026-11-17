import AppCore
import Auth
import Foundation

extension SettingsSecurityModel {
    public static var passkeyRegistrationSupported: Bool {
        if #available(iOS 17.4, *) { true } else { false }
    }
    public var canRegisterPasskey: Bool { registration != nil && Self.passkeyRegistrationSupported }

    public func loadPasskeys() async {
        let started = generation
        do {
            let result = try await perform(.listPasskeys)
            guard generation == started, !Task.isCancelled, case .passkeys(let list) = result else { return }
            passkeys = list
            passkeysUnavailable = false
            offline = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == started else { return }
            if case .offline? = error as? DataFailure { offline = true }
            if passkeys == nil { passkeysUnavailable = true }
        }
    }

    func submitPasskeyPrompt(_ prompt: SettingsSecurityPrompt, password: String) async {
        switch prompt {
        case .removePasskey:
            guard let target = removal else { return }
            guard await run(.removePasskey(id: target.id, current: password)) else { return }
            self.prompt = nil
            removal = nil
            passkeys?.removeAll { $0.id == target.id }
            message = "Passkey removed"
            await loadPasskeys()
        case .addPasskey:
            registrationCanceled = false
            let done = await run(
                .passkeyCreationOptions(current: password), work: { [self] in try await register(password: password) })
            if done {
                self.prompt = nil
                message = "Passkey added"
                await loadPasskeys()
            } else if registrationCanceled {
                registrationCanceled = false
                promptPassword = password
            } else if message == Self.registrationFailure || message == Self.registrationExpired {
                self.prompt = nil
            }
        default: break
        }
    }

    private func register(password: String) async throws -> AccountSecurityResult {
        guard let registration else { throw PasskeyFailure.unavailable }
        guard case .passkeyCreation(let challenge) = try await perform(.passkeyCreationOptions(current: password))
        else {
            throw DataFailure.server(status: nil)
        }
        _ = try Base64URL.decode(challenge.options.challenge)
        _ = try Base64URL.decode(challenge.options.user.id)
        guard !challenge.options.rp.id.isEmpty else { throw PasskeyFailure.unavailable }
        try Task.checkCancellation()
        let attestation = try await registration.registration(for: challenge)
        try Task.checkCancellation()
        return try await perform(
            .addPasskey(
                ApiPasskeyRegistrationInput(
                    challengeId: challenge.challengeId, name: deviceName, credential: attestation)))
    }
}

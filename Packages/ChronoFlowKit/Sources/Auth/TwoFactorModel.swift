import AppCore
import Foundation
import Observation

@MainActor @Observable public final class TwoFactorModel {
    public enum Mode: Hashable, Sendable { case code, recovery }
    public private(set) var mode: Mode = .code
    public private(set) var code = ""
    public private(set) var sessionFailure: SessionFailure?
    public let form = AuthFormModel(displayedFields: ["code"], context: .twoFactor)
    private let source: any DataSource
    private let navigation: AuthNavigation
    private let accept: @MainActor (SessionResult) async throws -> Void
    private var active = true
    public var field: String { mode == .code ? "code" : "recovery_code" }

    public init(
        source: any DataSource, navigation: AuthNavigation,
        accept: @escaping @MainActor (SessionResult) async throws -> Void
    ) {
        self.source = source
        self.navigation = navigation
        self.accept = accept
    }

    public func editCode(_ value: String) {
        guard active, !form.busy else { return }
        let nextCode = mode == .code ? String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) : value
        guard nextCode != code else { return }
        code = nextCode
        form.edit(field)
    }

    public func toggleMode() {
        guard active, !form.busy else { return }
        mode = mode == .code ? .recovery : .code
        code = ""
        sessionFailure = nil
        form.showFields([field])
    }

    public func validateChallenge() {
        guard let challenge = navigation.challengeID,
            !challenge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            cancel()
            return
        }
    }

    public func submit() async {
        validateChallenge()
        guard active, let challenge = navigation.challengeID, form.begin(.verify) else { return }
        sessionFailure = nil
        let proof: TwoFactorInput.Proof = mode == .code ? .code(code) : .recoveryCode(code)
        defer {
            code = ""
            form.finish()
        }
        do {
            try Task.checkCancellation()
            let result = try await source.completeTwoFactor(TwoFactorInput(challengeId: challenge, proof: proof))
            try Task.checkCancellation()
            guard active, navigation.challengeID == challenge else { return }
            code = ""
            try await accept(result)
            navigation.discardChallenge()
            active = false
        } catch {
            guard active, !(error is CancellationError) else { return }
            if let failure = error as? SessionFailure {
                sessionFailure = failure
            }
            form.receive(error as? DataFailure ?? .server(status: nil))
        }
    }

    public func cancel() {
        guard active else { return }
        active = false
        code = ""
        sessionFailure = nil
        form.clear()
        navigation.cancelTwoFactor()
    }
}

import AppCore
import Auth
import DesignSystem
import XCTest

nonisolated enum ResetSnapshotState: String, CaseIterable {
    case form, password, confirmation, server, throttle, offline, expired, done
}

@MainActor func resetSnapshotModel(_ state: ResetSnapshotState = .form) async throws -> ResetPasswordModel {
    let source = try recoverySource()
    try await source.requestPasswordReset(email: "demo@example.com")
    guard case .passwordReset(_, _, _, let input) = try await source.inbox().last else {
        throw DataFailure.server(status: nil)
    }
    let model = ResetPasswordModel(
        link: ResetPasswordLink(token: state == .expired ? "" : input.token, email: input.email), source: source,
        navigation: AuthNavigation())
    switch state {
    case .form, .expired: break
    case .password:
        model.form.receive(
            .validation(
                fields: [
                    "password": FieldMessage(key: "Use at least :min characters.", arguments: ["min": .number(12)])
                ], status: 422))
    case .confirmation:
        model.form.receive(
            .validation(
                fields: ["password_confirmation": FieldMessage(key: "The passwords don't match yet.")], status: 422))
    case .server: model.form.receive(.server(status: 503))
    case .throttle: model.form.receive(.throttled(retryAfterSeconds: 60, status: 429))
    case .offline: model.form.receive(.offline)
    case .done:
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        await model.submit()
    }
    return model
}

nonisolated final class ResetPasswordSnapshotTests: XCTestCase {
    @MainActor func testResetStatesInLeanSnapshotSet() async throws {
        try await recoverySnapshots(screen: "Reset", states: ResetSnapshotState.allCases, file: #filePath) {
            state, measure in
            ResetPasswordView(model: try await resetSnapshotModel(state), measure: measure)
        }
    }
}

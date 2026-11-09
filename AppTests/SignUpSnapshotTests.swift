import AppCore
import Auth
import DesignSystem
import XCTest

nonisolated enum SignUpSnapshotState: String, CaseIterable {
    case form, empty, email, taken, password, confirmation, visible, server, throttle, offline
}

@MainActor func signUpSnapshotModel(_ state: SignUpSnapshotState = .form) throws -> SignUpModel {
    let model = SignUpModel(
        source: try recoverySource(), navigation: AuthNavigation(),
        deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "test", accept: { _ in })
    if state != .empty {
        model.editName("Rick")
        model.editEmail("rick@example.com")
    }
    switch state {
    case .form: break
    case .empty:
        model.form.receive(
            .validation(
                fields: [
                    "name": FieldMessage(key: "Please fill this in."),
                    "email": FieldMessage(key: "Please fill this in."),
                    "password": FieldMessage(key: "Please fill this in."),
                    "password_confirmation": FieldMessage(key: "Please fill this in."),
                ], status: 422))
    case .email:
        model.form.receive(
            .validation(
                fields: ["email": FieldMessage(key: "Enter a valid email address, like name@example.com.")], status: 422
            ))
    case .taken:
        model.form.receive(
            .validation(fields: ["email": FieldMessage(key: "This email address is already in use.")], status: 422))
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
    case .visible:
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        model.togglePassword()
    case .server: model.form.receive(.server(status: 503))
    case .throttle: model.form.receive(.throttled(retryAfterSeconds: 60, status: 429))
    case .offline: model.form.receive(.offline)
    }
    return model
}

nonisolated final class SignUpSnapshotTests: XCTestCase {
    @MainActor func testSignUpStatesInLeanSnapshotSet() async throws {
        try await recoverySnapshots(screen: "SignUp", states: SignUpSnapshotState.allCases, file: #filePath) {
            state, measure in
            SignUpView(model: try signUpSnapshotModel(state), measure: measure)
        }
    }
}

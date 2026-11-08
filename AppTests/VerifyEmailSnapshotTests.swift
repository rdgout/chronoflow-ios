import AppCore
import Auth
import DataAccess
import DesignSystem
import XCTest

nonisolated enum VerifySnapshotState: String, CaseIterable {
    case waiting, countdown, failed, server, throttle, offline, failedServer, failedThrottle, failedOffline,
        signOutError
}

@MainActor func verifySnapshotModel(_ state: VerifySnapshotState = .waiting) async throws -> VerifyEmailModel {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let source = MockDataSource(seed: MockServerState(), now: { time }, delay: { 0 }, sleep: { _ in })
    let result = try await source.signUp(
        RegisterInput(
            name: "Rick", email: "rick@example.com", password: "NewPassword123!",
            passwordConfirmation: "NewPassword123!", deviceID: "0199a3c0-0000-7000-8000-000000000001",
            deviceName: "test"))
    let context = VerificationContext(accountID: result.account.id, email: result.account.email, epoch: 1)
    let model = VerifyEmailModel(
        context: context, source: source, now: { time }, current: { context }, persist: { _ in true }, route: {},
        discard: { throw DataFailure.offline })
    await model.activate()
    switch state {
    case .waiting: break
    case .countdown:
        await model.resend()
        model.form.clear()
    case .failed:
        model.receiveLink(nil)
        await model.check()
    case .failedServer, .failedThrottle, .failedOffline:
        model.receiveLink(nil)
        await model.check()
        if state == .failedThrottle {
            await model.resend()
        } else {
            model.form.receive(state == .failedOffline ? .offline : .server(status: 503))
        }
    case .server: model.form.receive(.server(status: 503))
    case .throttle: await model.resend()
    case .offline: model.form.receive(.offline)
    case .signOutError: await model.signOut()
    }
    return model
}

nonisolated final class VerifyEmailSnapshotTests: XCTestCase {
    @MainActor func testVerifyStatesInLeanSnapshotSet() async throws {
        try await recoverySnapshots(screen: "Verify", states: VerifySnapshotState.allCases, file: #filePath) {
            state, measure in
            VerifyEmailView(model: try await verifySnapshotModel(state), automaticallyChecks: false, measure: measure)
        }
    }
}

import Auth
import XCTest

nonisolated final class ResetPasswordLayoutTests: XCTestCase {
    @MainActor func testAllStatesFitSafeInsetsAndLastActionsScrollAboveKeyboard() async throws {
        for state in ResetSnapshotState.allCases {
            try await recoveryLayout { measure in
                ResetPasswordView(model: try await resetSnapshotModel(state), measure: measure)
            }
        }
    }
}

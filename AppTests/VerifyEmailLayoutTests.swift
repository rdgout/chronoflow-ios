import Auth
import XCTest

nonisolated final class VerifyEmailLayoutTests: XCTestCase {
    @MainActor func testWaitingFailedAndErrorActionsFitTheLeanDeviceProfiles() async throws {
        for state in VerifySnapshotState.allCases {
            try await recoveryLayout { measure in
                VerifyEmailView(
                    model: try await verifySnapshotModel(state), automaticallyChecks: false, measure: measure)
            }
        }
    }
}

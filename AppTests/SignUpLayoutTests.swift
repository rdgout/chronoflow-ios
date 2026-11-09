import Auth
import XCTest

nonisolated final class SignUpLayoutTests: XCTestCase {
    @MainActor func testAllStatesKeepConsentToggleAndFooterReachableAtXXLarge() async throws {
        for state in SignUpSnapshotState.allCases {
            try await recoveryLayout { measure in SignUpView(model: try signUpSnapshotModel(state), measure: measure) }
        }
    }
}

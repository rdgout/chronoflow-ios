import Auth
import DesignSystem
import UIKit
import XCTest

nonisolated final class VerifyEmailControlTests: XCTestCase {
    @MainActor func testWaitingCountdownAndFailedHaveNoInputsAndKeepLargeActions() async throws {
        try await AuthTestHost.registerFonts()
        for state in [VerifySnapshotState.waiting, .countdown, .failed] {
            let model = try await verifySnapshotModel(state)
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                VerifyEmailView(model: model, automaticallyChecks: false, measure: { frames[$0] = $1 }),
                size: SnapshotDevice.all()[0].size)
            defer { host.close() }
            try await host.settle()
            XCTAssertTrue(recoveryTextFields(host.window).isEmpty)
            if state == .failed {
                XCTAssertEqual(try XCTUnwrap(frames[.submit]).height, AuthTokens.footerHeight, accuracy: 0.5)
                XCTAssertEqual(try XCTUnwrap(frames[.resend]).height, AuthTokens.footerHeight, accuracy: 0.5)
            }
        }
    }
}

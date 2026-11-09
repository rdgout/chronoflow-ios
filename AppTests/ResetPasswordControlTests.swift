import Auth
import DesignSystem
import UIKit
import XCTest

nonisolated final class ResetPasswordControlTests: XCTestCase {
    @MainActor func testExpiredAndDoneActionsUseTheBoardLargeButtonHeight() async throws {
        try await AuthTestHost.registerFonts()
        for state in [ResetSnapshotState.expired, .done] {
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                ResetPasswordView(model: try await resetSnapshotModel(state), measure: { frames[$0] = $1 }),
                size: SnapshotDevice.all()[0].size)
            defer { host.close() }
            try await host.settle()
            XCTAssertEqual(try XCTUnwrap(frames[.submit]).height, AuthTokens.footerHeight, accuracy: 0.5)
        }
    }

    @MainActor func testNewPasswordAutoFillReturnChainAndServerErrors() async throws {
        try await AuthTestHost.registerFonts()
        let model = try await resetSnapshotModel()
        let host = try AuthTestHost(ResetPasswordView(model: model), size: SnapshotDevice.all()[0].size)
        defer { host.close() }
        try await host.settle()
        let fields = recoveryTextFields(host.window)
        XCTAssertEqual(fields.count, 2)
        for field in fields {
            XCTAssertTrue(field.isSecureTextEntry)
            XCTAssertEqual(field.textContentType, .newPassword)
            XCTAssertEqual(field.autocapitalizationType, .none)
        }
        XCTAssertEqual(fields.first?.returnKeyType, .next)
        XCTAssertEqual(fields.last?.returnKeyType, .go)
        model.editPassword("short")
        model.editConfirmation("different")
        await model.submit()
        try await host.settle {
            model.password.isEmpty && model.confirmation.isEmpty && !model.form.fields.isEmpty
                && recoveryTextFields(host.window).count == 2
                && recoveryTextFields(host.window).allSatisfy { ($0.text ?? "").isEmpty }
        }
        XCTAssertTrue(model.password.isEmpty && model.confirmation.isEmpty)
        XCTAssertFalse(model.form.fields.isEmpty)
        XCTAssertTrue(recoveryTextFields(host.window).allSatisfy { ($0.text ?? "").isEmpty })
    }
}

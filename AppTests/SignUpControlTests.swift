import Auth
import DesignSystem
import UIKit
import XCTest

nonisolated final class SignUpControlTests: XCTestCase {
    @MainActor func testSharedVisibilityPreservesValuesAutoFillAndNativeNameTraits() async throws {
        try await AuthTestHost.registerFonts()
        let model = try signUpSnapshotModel()
        let host = try AuthTestHost(SignUpView(model: model), size: SnapshotDevice.all()[0].size)
        defer { host.close() }
        model.editPassword("NewPassword123!")
        model.editConfirmation("NewPassword123!")
        for visible in [false, true, false] {
            if model.showsPassword != visible { model.togglePassword() }
            try await host.settle()
            let fields = recoveryTextFields(host.window)
            XCTAssertEqual(fields.count, 4)
            XCTAssertEqual(fields[0].textContentType, .name)
            XCTAssertEqual(fields[0].autocapitalizationType, .words)
            XCTAssertEqual(fields[1].keyboardType, .emailAddress)
            XCTAssertEqual(fields[1].textContentType, .emailAddress)
            for field in fields.suffix(2) {
                XCTAssertEqual(field.isSecureTextEntry, !visible)
                XCTAssertEqual(field.textContentType, .newPassword)
                XCTAssertEqual(field.text, "NewPassword123!")
            }
            XCTAssertEqual(fields.last?.returnKeyType, .go)
        }
    }
}

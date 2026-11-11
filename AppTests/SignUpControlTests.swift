import AppCore
import Auth
import DesignSystem
import UIKit
import XCTest

nonisolated final class SignUpControlTests: XCTestCase {
    @MainActor func testMixedFailureFocusesAndRevealsTheConfirmationMessage() async throws {
        try await AuthTestHost.registerFonts()
        for category in [UIContentSizeCategory.large, .extraExtraLarge] {
            let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
            let model = try signUpSnapshotModel()
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                SignUpView(model: model, measure: { frames[$0] = $1 }), size: fixture.size, insets: fixture.insets,
                category: category, scale: fixture.scale)
            defer { host.close() }
            try await host.settle()
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            model.form.receive(
                .validation(
                    fields: [
                        "email": FieldMessage(key: "This email address is already in use."),
                        "password_confirmation": FieldMessage(key: "The passwords don't match yet."),
                    ], status: 422))
            let revealed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    guard let field = recoveryTextFields(host.window).last,
                        field.isFirstResponder, let confirmation = frames[.confirmation]
                    else { return false }
                    var viewport = scroll.convert(scroll.bounds, to: host.window).intersection(host.window.bounds)
                    let keyboard = host.window.keyboardLayoutGuide.layoutFrame
                    if keyboard.height > 0 {
                        viewport.size.height = max(0, min(viewport.maxY, keyboard.minY) - viewport.minY)
                    }
                    return viewport.contains(confirmation)
                }, object: nil)
            await fulfillment(of: [revealed], timeout: 6)
            XCTAssertEqual(model.form.banner, .emailTaken)
            XCTAssertNotNil(model.form.fields["password_confirmation"])
        }
    }

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

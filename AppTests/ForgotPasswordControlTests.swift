import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordControlTests: XCTestCase {
    @MainActor func testEmailAutoFillAndFormLockPreserveFieldAndRestoreErrorFocus() async throws {
        try await FontRegistry.register()
        for language in ["en", "nl"] {
            let model = await forgotPasswordSnapshotModel()
            let host = try AuthTestHost(
                ForgotPasswordView(model: model), size: SnapshotDevice.all()[0].size, language: language)
            defer { host.close() }
            try await host.settle()
            let field = try XCTUnwrap(forgotTextFields(host.window).first)
            XCTAssertEqual(field.textContentType, .emailAddress)
            XCTAssertEqual(field.keyboardType, .emailAddress)
            XCTAssertEqual(field.returnKeyType, .send)
            XCTAssertTrue(field.becomeFirstResponder())
            for failure in [
                DataFailure.server(status: 503),
                .validation(fields: ["email": FieldMessage(key: "Please fill this in.")], status: 422),
                .throttled(retryAfterSeconds: 60, status: 429), .offline,
            ] {
                XCTAssertTrue(model.form.begin(.sendResetLink))
                try await host.settle()
                XCTAssertFalse(field.isFirstResponder)
                XCTAssertFalse(field.isEnabled)
                model.form.receive(failure)
                model.form.finish()
                try await host.settle()
                XCTAssertTrue(field.isEnabled)
                XCTAssertTrue(field.isFirstResponder)
                XCTAssertTrue(forgotTextFields(host.window).first === field)
                XCTAssertEqual(model.form.failure, failure)
            }
        }
    }

    @MainActor func testSentStateReplacesTheInputAndKeepsTheSharedScrollBehavior() async throws {
        try await FontRegistry.register()
        for sent in [false, true] {
            let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
            let host = try AuthTestHost(
                ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent)), size: fixture.size,
                insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            try await host.settle()
            XCTAssertEqual(forgotTextFields(host.window).count, sent ? 0 : 1)
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            XCTAssertTrue(scroll.isScrollEnabled && scroll.bounces && scroll.alwaysBounceVertical)
            XCTAssertTrue(
                [UIScrollView.KeyboardDismissMode.interactive, .interactiveWithAccessory].contains(
                    scroll.keyboardDismissMode))
        }
    }
}

@MainActor private func forgotTextFields(_ view: UIView) -> [UITextField] {
    (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(forgotTextFields)
}

import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordControlTests: XCTestCase {
    @MainActor func testEmailAutoFillAndFormLockPreserveFieldAndRestoreErrorFocus() async throws {
        try await AuthTestHost.registerFonts()
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
            let failures: [(DataFailure, AuthBannerKind?)] = [
                (.server(status: 503), .server),
                (.validation(fields: ["email": FieldMessage(key: "Please fill this in.")], status: 422), nil),
                (.throttled(retryAfterSeconds: 60, status: 429), .locked), (.offline, nil),
            ]
            for (failure, banner) in failures {
                XCTAssertTrue(model.form.begin(.sendResetLink))
                try await host.settle()
                XCTAssertFalse(field.isFirstResponder)
                XCTAssertFalse(field.isEnabled)
                model.form.receive(failure)
                model.form.finish()
                try await host.settle()
                model.editEmail(try XCTUnwrap(field.text))
                XCTAssertTrue(field.isEnabled)
                XCTAssertTrue(field.isFirstResponder)
                XCTAssertTrue(forgotTextFields(host.window).first === field)
                XCTAssertEqual(model.form.failure, failure)
                XCTAssertEqual(model.form.banner, banner)
            }
        }
    }

    @MainActor func testPrefilledNativeEmailInheritsTheWindowRootCap() async throws {
        try await AuthTestHost.registerFonts()
        let host = try AuthTestHost(EmptyView(), size: SnapshotDevice.all()[0].size)
        defer { host.close() }
        for category in [UIContentSizeCategory.small, .extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            host.configure(ForgotPasswordView(model: await forgotPasswordSnapshotModel()), category: category)
            try await host.settle()
            let field = try XCTUnwrap(forgotTextFields(host.window).first)
            let effective = ContentSizeCap.clamp(category)
            XCTAssertEqual(field.traitCollection.preferredContentSizeCategory, effective)
            XCTAssertEqual(
                try XCTUnwrap(field.font).pointSize,
                Typography.authBody.uiFont(compatibleWith: UITraitCollection(preferredContentSizeCategory: effective))
                    .pointSize, accuracy: 0.01)
            XCTAssertEqual(field.text, "rick@example.com")
        }
    }

    @MainActor func testSentStateReplacesTheInputAndKeepsTheSharedScrollBehavior() async throws {
        try await AuthTestHost.registerFonts()
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

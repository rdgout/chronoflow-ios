import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordControlTests: XCTestCase {
    @MainActor func testRootCapMakesAX5EqualXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        var expected: SnapshotRaster?
        var expectedFrames: [AuthElement: CGRect] = [:]
        var expectedInput: CGRect?
        var expectedText: CGRect?
        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            var frames: [AuthElement: CGRect] = [:]
            let measure: (AuthElement, CGRect) -> Void = { frames[$0] = $1 }
            host.configure(
                ForgotPasswordView(model: await forgotPasswordSnapshotModel(state: .fieldError), measure: measure),
                category: category)
            try await host.settle()
            let actual = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            let field = try XCTUnwrap(forgotPasswordNativeField(in: host.window))
            let input = field.convert(field.bounds, to: host.window)
            let text = field.convert(field.textRect(forBounds: field.bounds), to: host.window)
            let context =
                "SE, en, light, requested=\(category.rawValue), nativeCategory=\(field.traitCollection.preferredContentSizeCategory.rawValue), resolvedFont=\(String(describing: field.font))"
            XCTAssertNil(
                AuthSnapshotCapture.failure(
                    raster: actual, size: fixture.size, scale: fixture.scale,
                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                    frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                    required: Set(["brand", "heading", "card", "email", "submit"])))
            if let expected {
                XCTAssertEqual(Set(frames.keys), Set(expectedFrames.keys))
                for element in expectedFrames.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    XCTAssertEqual(frames[element], expectedFrames[element], "AX5 frame differs: \(element)")
                }
                XCTAssertTrue(
                    AuthSnapshotCapture.nativeInputRectsMatch(text, try XCTUnwrap(expectedText), scale: host.scale),
                    "AX5 native text rect differs by more than one device pixel: \(text) vs \(String(describing: expectedText)), \(context)"
                )
                XCTAssertTrue(
                    AuthSnapshotCapture.pixelsMatchOutsideNativeInput(
                        actual, expected, input: input, referenceInput: try XCTUnwrap(expectedInput), scale: host.scale),
                    "AX5 native input differs by more than one device pixel, or pixels differ outside its expanded union: \(input) vs \(String(describing: expectedInput)), \(context)"
                )
            } else {
                expected = actual
                expectedFrames = frames
                expectedInput = input
                expectedText = text
            }
        }
    }

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
                (.throttled(retryAfterSeconds: 60, status: 429), .locked), (.offline, .offline),
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

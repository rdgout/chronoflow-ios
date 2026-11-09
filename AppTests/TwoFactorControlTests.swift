import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorControlTests: XCTestCase {
    @MainActor func testRootCapMakesAX5EqualXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        var expected: SnapshotRaster?
        var expectedFrames: [AuthElement: CGRect] = [:]
        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            var frames: [AuthElement: CGRect] = [:]
            let measure: (AuthElement, CGRect) -> Void = { frames[$0] = $1 }
            host.configure(
                TwoFactorView(model: twoFactorSnapshotModel(recovery: true, state: .fieldError), measure: measure),
                category: category)
            try await host.settle()
            let actual = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
            XCTAssertNil(
                AuthSnapshotCapture.failure(
                    raster: actual, size: fixture.size, scale: fixture.scale,
                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                    frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                    required: Set(["brand", "heading", "card", "submit"])))
            if let expected {
                XCTAssertEqual(Set(frames.keys), Set(expectedFrames.keys))
                for element in expectedFrames.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                    XCTAssertEqual(frames[element], expectedFrames[element], "AX5 frame differs: \(element)")
                }
                XCTAssertTrue(actual == expected, "AX5 pixels differ from xxLarge: SE, en, light")
            } else {
                expected = actual
                expectedFrames = frames
            }
        }
    }

    @MainActor func testRecoveryPlaceholderSurvivesErrorsAndClearsWhenReturningToCode() async throws {
        try await AuthTestHost.registerFonts()
        for language in ["en", "nl"] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let model = twoFactorSnapshotModel(recovery: true, state: .fieldError)
                let host = try AuthTestHost(
                    TwoFactorView(model: model), size: SnapshotDevice.all()[0].size, style: style, language: language)
                defer { host.close() }
                try await host.settle()
                let recovery = try XCTUnwrap(textFields(host.window).first)
                XCTAssertEqual(recovery.placeholder, "xxxx-xxxx")
                XCTAssertEqual(recovery.text, "")
                model.toggleMode()
                try await host.settle()
                let code = try XCTUnwrap(textFields(host.window).first)
                XCTAssertTrue(code.placeholder?.isEmpty != false)
                XCTAssertEqual(code.text, "")
            }
        }
    }

    @MainActor func testFailedAttemptsRefocusTheEnabledFieldWithoutEditingAwayFeedback() async throws {
        try await AuthTestHost.registerFonts()
        for recovery in [false, true] {
            let model = twoFactorSnapshotModel(recovery: recovery)
            let host = try AuthTestHost(TwoFactorView(model: model), size: SnapshotDevice.all()[0].size)
            defer { host.close() }
            try await host.settle()
            let field = try XCTUnwrap(textFields(host.window).first)
            XCTAssertTrue(field.becomeFirstResponder())
            for failure in [
                DataFailure.server(status: 503),
                .validation(fields: [model.field: FieldMessage(key: "Please fill this in.")], status: 422),
            ] {
                XCTAssertTrue(model.form.begin(.verify))
                try await host.settle()
                XCTAssertFalse(field.isFirstResponder)
                XCTAssertFalse(field.isEnabled)
                model.form.receive(failure)
                model.form.finish()
                try await host.settle()
                XCTAssertTrue(field.isEnabled)
                XCTAssertTrue(field.isFirstResponder)
                XCTAssertTrue(textFields(host.window).first === field)
                XCTAssertEqual(model.form.failure, failure)
                XCTAssertEqual(model.form.banner, failure == .server(status: 503) ? .server : nil)
                XCTAssertEqual(model.form.fields.isEmpty, failure == .server(status: 503))
            }
        }
    }

    @MainActor func testBothModesKeepInteractiveKeyboardDismissalAndVerticalBouncing() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
        for recovery in [false, true] {
            let model = twoFactorSnapshotModel(recovery: recovery)
            let host = try AuthTestHost(
                TwoFactorView(model: model), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            try await host.settle()
            let field = try XCTUnwrap(textFields(host.window).first)
            var parent = field.superview
            while parent != nil && !(parent is UIScrollView) { parent = parent?.superview }
            let scroll = try XCTUnwrap(parent as? UIScrollView)
            XCTAssertTrue(scroll.isScrollEnabled)
            XCTAssertTrue(scroll.bounces)
            XCTAssertTrue(scroll.alwaysBounceVertical)
            let interactiveModes: Set<UIScrollView.KeyboardDismissMode> = [.interactive, .interactiveWithAccessory]
            XCTAssertTrue(interactiveModes.contains(scroll.keyboardDismissMode), "\(scroll.keyboardDismissMode)")
        }
    }

    @MainActor func testDisplayedCodeRejectsOverflowAndNonDigitsEvenWhenTheModelDoesNotChange() async throws {
        try await AuthTestHost.registerFonts()
        let model = twoFactorSnapshotModel()
        let host = try AuthTestHost(TwoFactorView(model: model), size: SnapshotDevice.all()[0].size)
        defer { host.close() }
        try await host.settle()
        let field = try XCTUnwrap(textFields(host.window).first)
        XCTAssertTrue(field.becomeFirstResponder())
        for (input, expected) in [("a٣", ""), ("12b٣345678", "123456"), ("7", "123456"), ("x", "123456")] {
            field.insertText(input)
            try await host.settle()
            XCTAssertEqual(model.code, expected)
            XCTAssertEqual(field.text, expected)
            XCTAssertTrue(field.isFirstResponder)
            XCTAssertFalse(model.form.busy)
        }
    }

    @MainActor func testBothDisplayedProofsFollowModelEditsAndAttemptClearingWithoutErasingErrors() async throws {
        try await AuthTestHost.registerFonts()
        for recovery in [false, true] {
            let model = twoFactorSnapshotModel(recovery: recovery)
            let host = try AuthTestHost(TwoFactorView(model: model), size: SnapshotDevice.all()[0].size)
            defer { host.close() }
            try await host.settle()
            let field = try XCTUnwrap(textFields(host.window).first)
            XCTAssertTrue(field.becomeFirstResponder())
            let input = recovery ? "AbCdEf1234-GhIjKl5678" : "123456"
            field.insertText(input)
            try await host.settle()
            XCTAssertEqual(model.code, input)
            XCTAssertEqual(field.text, input)
            model.editCode(recovery ? "OtherCode-123" : "654321")
            try await host.settle()
            XCTAssertEqual(field.text, model.code)
            await model.submit()
            try await host.settle()
            XCTAssertEqual(field.text, "")
            XCTAssertEqual(model.code, "")
            XCTAssertNotNil(model.form.fields[model.field])
            XCTAssertNil(model.form.banner)
        }
    }

    @MainActor func testNativeInputTraitsAndModeToggleDiscardTheOldKeyboardConfiguration() async throws {
        try await AuthTestHost.registerFonts()
        let model = twoFactorSnapshotModel()
        let host = try AuthTestHost(TwoFactorView(model: model), size: SnapshotDevice.all()[0].size)
        defer { host.close() }
        try await host.settle()
        let code = try XCTUnwrap(textFields(host.window).first)
        XCTAssertEqual(code.keyboardType, .numberPad)
        XCTAssertEqual(code.textContentType, .oneTimeCode)
        XCTAssertEqual(code.autocapitalizationType, .none)
        XCTAssertEqual(code.autocorrectionType, .no)
        model.toggleMode()
        try await host.settle()
        let recovery = try XCTUnwrap(textFields(host.window).first)
        XCTAssertEqual(recovery.keyboardType, .default)
        XCTAssertTrue(recovery.textContentType == nil || recovery.textContentType.rawValue.isEmpty)
        XCTAssertEqual(recovery.returnKeyType, .go)
        XCTAssertEqual(recovery.autocapitalizationType, .none)
        XCTAssertEqual(recovery.autocorrectionType, .no)
        XCTAssertFalse(code === recovery)
    }

    @MainActor func testVerifyKeepsItsLabelAndSizeWhileBusyInBothLanguages() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        for language in ["en", "nl"] {
            var frames: [AuthElement: CGRect] = [:]
            let model = twoFactorSnapshotModel()
            let host = try AuthTestHost(
                TwoFactorView(model: model) { frames[$0] = $1 }, size: fixture.size, insets: fixture.insets,
                language: language, category: .extraExtraLarge)
            defer { host.close() }
            try await host.settle()
            let idle = try XCTUnwrap(frames[.submit]).size
            XCTAssertTrue(model.form.begin(.verify))
            try await host.settle()
            XCTAssertEqual(try XCTUnwrap(frames[.submit]).size, idle)
            model.form.finish()
        }
    }

    @MainActor private func textFields(_ view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(textFields)
    }
}

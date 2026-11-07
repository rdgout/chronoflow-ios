import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorControlTests: XCTestCase {
    @MainActor func testBothModesKeepInteractiveKeyboardDismissalAndVerticalBouncing() async throws {
        try await FontRegistry.register()
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
            XCTAssertEqual(scroll.keyboardDismissMode, .interactive)
        }
    }

    @MainActor func testDisplayedCodeRejectsOverflowAndNonDigitsEvenWhenTheModelDoesNotChange() async throws {
        try await FontRegistry.register()
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
        try await FontRegistry.register()
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
        try await FontRegistry.register()
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
        try await FontRegistry.register()
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

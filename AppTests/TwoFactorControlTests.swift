import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorControlTests: XCTestCase {
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

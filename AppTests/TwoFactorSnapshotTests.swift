import AppCore
import Auth
import DataAccess
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorSnapshotTests: XCTestCase {
    @MainActor func testCodeAndRecoveryStatesAtEveryD1cProfileSize() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for category in try fixture.categories {
                        for recovery in [false, true] {
                            for state in TwoFactorSnapshotState.allCases {
                                var frames: [AuthElement: CGRect] = [:]
                                host.configure(
                                    TwoFactorView(
                                        model: twoFactorSnapshotModel(recovery: recovery, state: state),
                                        measure: { frames[$0] = $1 }),
                                    style: style, language: language, category: category)
                                try await host.settle()
                                let suffix =
                                    "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(DynamicTypeSize(category).map { String(describing: $0) } ?? category.rawValue)-\(recovery ? "recovery" : "code")-\(state.rawValue)"
                                let directory = URL(filePath: #filePath).deletingLastPathComponent()
                                    .appending(path: "__Snapshots__/Auth/TwoFactor")
                                let failure = try AuthSnapshotCapture.verify(
                                    png: XCTUnwrap(host.image().pngData()),
                                    size: fixture.size, scale: fixture.scale,
                                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                                    frames: Dictionary(
                                        uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                                    required: Set(
                                        (Set([AuthElement.brand, .heading, .card, .code, .submit, .modeToggle])).map(
                                            \.rawValue)),
                                    reference: directory.appending(path: "\(suffix).png"),
                                    record: ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1")
                                if ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" {
                                    XCTAssertTrue(failure?.hasPrefix("Record mode is on.") == true)
                                } else if let failure {
                                    XCTFail(failure)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor func testRootCapMakesAX5EqualXXLargeInBothModesLanguagesAndAppearances() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for recovery in [false, true] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        var expected: SnapshotRaster?
                        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
                            var frames: [AuthElement: CGRect] = [:]
                            host.configure(
                                TwoFactorView(
                                    model: twoFactorSnapshotModel(recovery: recovery, state: .fieldError),
                                    measure: { frames[$0] = $1 }),
                                style: style, language: language, category: category)
                            try await host.settle()
                            let actual = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                            XCTAssertNil(
                                AuthSnapshotCapture.failure(
                                    raster: actual, size: fixture.size, scale: fixture.scale,
                                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                                    frames: Dictionary(
                                        uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                                    required: Set(["brand", "heading", "card", "submit"])))
                            if let expected { XCTAssertEqual(actual, expected) } else { expected = actual }
                        }
                    }
                }
            }
        }
    }
}

nonisolated enum TwoFactorSnapshotState: String, CaseIterable { case none, fieldError, attempts, server }

@MainActor func twoFactorSnapshotModel(
    recovery: Bool = false, state: TwoFactorSnapshotState = .none
) -> TwoFactorModel {
    let navigation = AuthNavigation()
    navigation.twoFactor(challengeID: "snapshot-challenge")
    let model = TwoFactorModel(source: MockDataSource(delay: { 0 }, sleep: { _ in }), navigation: navigation) { _ in }
    if recovery { model.toggleMode() }
    switch state {
    case .none: break
    case .fieldError:
        model.form.receive(
            .validation(
                fields: [
                    model.field: FieldMessage(
                        key: recovery
                            ? "This recovery code was not accepted. Try another saved code."
                            : "The authentication code was not accepted. Try again.")
                ], status: 422))
    case .attempts: model.form.receive(.throttled(retryAfterSeconds: 60, status: 429))
    case .server: model.form.receive(.server(status: 500))
    }
    return model
}

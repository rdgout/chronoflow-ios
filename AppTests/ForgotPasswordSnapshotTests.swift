import AppCore
import Auth
import DataAccess
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordSnapshotTests: XCTestCase {
    @MainActor func testForgotStatesAtEveryD1cProfileSize() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for category in try fixture.categories {
                        for sent in [false, true] {
                            for state in sent ? [.none] : ForgotPasswordSnapshotState.allCases {
                                var frames: [AuthElement: CGRect] = [:]
                                host.configure(
                                    ForgotPasswordView(
                                        model: await forgotPasswordSnapshotModel(sent: sent, state: state),
                                        measure: { frames[$0] = $1 }),
                                    style: style, language: language, category: category)
                                try await host.settle()
                                let suffix =
                                    "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(DynamicTypeSize(category).map { String(describing: $0) } ?? category.rawValue)-\(sent ? "sent" : "form")-\(state.rawValue)"
                                let directory = URL(filePath: #filePath).deletingLastPathComponent()
                                    .appending(path: "__Snapshots__/Auth/Forgot")
                                let failure = try AuthSnapshotCapture.verify(
                                    png: XCTUnwrap(host.image().pngData()),
                                    size: fixture.size, scale: fixture.scale,
                                    viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                                    frames: Dictionary(
                                        uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                                    required: Set(
                                        (Set([AuthElement.brand, .heading, .subtitle, .card])
                                            .union(sent ? [.notice, .openEmail, .backToSignIn] : [.email, .submit]))
                                            .map(
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

    @MainActor func testRootCapMakesAX5EqualXXLargeInBothStatesLanguagesAndAppearances() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for sent in [false, true] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        var expected: SnapshotRaster?
                        for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
                            var frames: [AuthElement: CGRect] = [:]
                            host.configure(
                                ForgotPasswordView(
                                    model: await forgotPasswordSnapshotModel(sent: sent, state: .fieldError),
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
                                    required: Set(["brand", "heading", "card"])
                                        .union(sent ? ["notice", "openEmail", "backToSignIn"] : ["email", "submit"])))
                            if let expected { XCTAssertEqual(actual, expected) } else { expected = actual }
                        }
                    }
                }
            }
        }
    }
}

nonisolated enum ForgotPasswordSnapshotState: String, CaseIterable { case none, fieldError, attempts, server, offline }

@MainActor func forgotPasswordSnapshotModel(sent: Bool = false, state: ForgotPasswordSnapshotState = .none) async
    -> ForgotPasswordModel
{
    let model = ForgotPasswordModel(
        source: MockDataSource(delay: { 0 }, sleep: { _ in }), navigation: AuthNavigation(), email: "rick@example.com")
    if sent {
        await model.submit()
        return model
    }
    switch state {
    case .none: break
    case .fieldError:
        model.form.receive(
            .validation(
                fields: ["email": FieldMessage(key: "Enter a valid email address, like name@example.com.")], status: 422
            ))
    case .attempts: model.form.receive(.throttled(retryAfterSeconds: 60, status: 429))
    case .server: model.form.receive(.server(status: 500))
    case .offline: model.form.receive(.offline)
    }
    return model
}

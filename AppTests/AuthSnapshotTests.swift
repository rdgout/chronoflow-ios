import AppCore
import Auth
import DataAccess
import DesignSystem
import Foundation
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSnapshotTests: XCTestCase {
    @MainActor func testSignInStatesInLeanSnapshotSet() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.authSnapshotProfiles() {
            let host = try AuthTestHost(
                EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            for (style, language, category) in fixture.authSnapshotVariants {
                print("Sign in snapshots: \(fixture.snapshotName), \(style), \(language), \(category.rawValue)")
                for banner in [nil] + AuthBannerKind.allCases.map(Optional.some) {
                    let model = authSnapshotModel()
                    if let banner { model.form.receive(snapshotFailure(banner)) }
                    XCTAssertEqual(model.form.banner, banner)
                    var frames: [AuthElement: CGRect] = [:]
                    let view = SignInView(model: model, back: {}, guest: {}, measure: { frames[$0] = $1 })
                    host.configure(view, style: style, language: language, category: category)
                    try await host.settle()
                    let suffix =
                        "\(fixture.snapshotName)-\(style == .dark ? "dark" : "light")-\(language)-\(DynamicTypeSize(category).map { String(describing: $0) } ?? category.rawValue)-\(banner?.rawValue ?? "none")"
                    let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(
                        path: "__Snapshots__/Auth")
                    let reference = directory.appending(path: "\(suffix).png")
                    let failure = try AuthSnapshotCapture.verify(
                        png: XCTUnwrap(host.image().pngData()),
                        size: fixture.size, scale: fixture.scale,
                        viewport: CGRect(origin: .zero, size: fixture.size).inset(by: fixture.insets),
                        frames: Dictionary(uniqueKeysWithValues: frames.map { ($0.key.rawValue, $0.value) }),
                        required: Set(
                            (Set(AuthElement.allCases).subtracting([
                                .code, .modeToggle, .notice, .openEmail, .backToSignIn,
                            ])).map(\.rawValue)),
                        reference: reference,
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
                SignInView(model: authSnapshotModel(), back: {}, guest: {}, measure: measure), category: category)
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
}

@MainActor func authSnapshotModel() -> SignInModel {
    SignInModel(
        source: MockDataSource(delay: { 0 }, sleep: { _ in }),
        session: SessionController(credentials: AuthSnapshotCredentials(), accounts: AuthSnapshotAccounts()),
        deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "snapshot", route: { _ in })
}
nonisolated func snapshotFailure(_ banner: AuthBannerKind) -> DataFailure {
    switch banner {
    case .credentials:
        .validation(fields: ["email": FieldMessage(key: "These sign-in details don't match our records.")], status: 422)
    case .locked: .throttled(retryAfterSeconds: 60, status: 429)
    case .server: .server(status: 500)
    }
}
private actor AuthSnapshotCredentials: SessionStore {
    func read() -> Data? { nil }
    func write(_ data: Data) {}
    func delete() {}
}
private actor AuthSnapshotAccounts: SessionAccountStore {
    func open(accountID: AccountID) {}
    func upsert(_ account: SessionAccount) {}
    func close() {}
}

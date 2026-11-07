import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthLayoutTests: XCTestCase {
    @MainActor func testSafeAreaFixturesAreAppliedAndAllContentStaysInsideHorizontalBounds() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    var frames: [AuthElement: CGRect] = [:]
                    let model = authSnapshotModel()
                    model.form.receive(snapshotFailure(.credentials))
                    let host = try AuthTestHost(
                        SignInView(model: model, back: {}, guest: {}, measure: { frames[$0] = $1 }), size: fixture.size,
                        insets: fixture.insets, language: language, category: category, scale: fixture.scale)
                    defer { host.close() }
                    try await host.settle()
                    XCTAssertEqual(
                        Set(frames.keys),
                        Set(AuthElement.allCases).subtracting([.code, .modeToggle, .notice, .openEmail, .backToSignIn]))
                    let brand = try XCTUnwrap(frames[.brand])
                    XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                    XCTAssertEqual(brand.minX, fixture.insets.left + AuthTokens.gutter, accuracy: 0.5)
                    XCTAssertEqual(
                        brand.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter, accuracy: 0.5)
                    for frame in frames.values {
                        XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                        XCTAssertLessThanOrEqual(
                            frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                        XCTAssertGreaterThan(frame.height, 0)
                    }
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.submit]).height, AuthTokens.touch)
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.footer]).height, AuthTokens.footerHeight)
                    XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                }
            }
        }
    }

    @MainActor func testEnglishLinksReachBothCardEdgesAtWideDeviceSizes() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() where ["18promax", "duo"].contains(fixture.name) {
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                SignInView(model: authSnapshotModel(), back: {}, guest: {}, measure: { frames[$0] = $1 }),
                size: fixture.size, insets: fixture.insets)
            defer { host.close() }
            try await host.settle()
            let card = try XCTUnwrap(frames[.card])
            let forgot = try XCTUnwrap(frames[.forgot])
            let signup = try XCTUnwrap(frames[.signup])
            XCTAssertEqual(forgot.minY, signup.minY, accuracy: 0.5)
            XCTAssertEqual(forgot.minX, card.minX + AuthTokens.cardPadding, accuracy: 0.5)
            XCTAssertEqual(signup.maxX, card.maxX - AuthTokens.cardPadding, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(signup.minX - forgot.maxX, AuthTokens.fieldGap)
        }
    }

    @MainActor func testWrappedDutchLinkKeepsTheGeneratedLineHeight() async throws {
        try await FontRegistry.register()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        var frames: [AuthElement: CGRect] = [:]
        let host = try AuthTestHost(
            SignInView(model: authSnapshotModel(), back: {}, guest: {}, measure: { frames[$0] = $1 })
                .frame(width: AuthTokens.touch * 5),
            size: fixture.size, insets: fixture.insets, language: "nl", category: .extraExtraLarge)
        defer { host.close() }
        try await host.settle()
        for (element, style) in [
            (AuthElement.forgotLabel, Typography.authLabel), (.signupLabel, Typography.authStrong),
        ] {
            let label = try XCTUnwrap(frames[element])
            let font = style.uiFont(compatibleWith: host.controller.traitCollection)
            let lineHeight = try XCTUnwrap(style.lineHeight) * font.pointSize / style.size
            XCTAssertEqual(label.height / lineHeight, (label.height / lineHeight).rounded(), accuracy: 0.05)
        }
        XCTAssertGreaterThan(try XCTUnwrap(frames[.forgotLabel]).height, AuthTokens.touch)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[.signup]).minY, try XCTUnwrap(frames[.forgot]).maxY)
    }
}

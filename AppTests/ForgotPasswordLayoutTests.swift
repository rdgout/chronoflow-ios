import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordLayoutTests: XCTestCase {
    @MainActor func testLastControlCanScrollAboveKeyboardInsetsOnDuoAndSE() async throws {
        try await FontRegistry.register()
        // Duo's saved visible keyboard begins at 414 of 678 points; SE's keyboard is 218 points tall.
        for (alias, keyboardInset) in [("duo", CGFloat(264)), ("se", CGFloat(218))] {
            let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == alias })
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for sent in [false, true] {
                        var frames: [AuthElement: CGRect] = [:]
                        var insets = fixture.insets
                        insets.bottom = max(insets.bottom, keyboardInset)
                        let host = try AuthTestHost(
                            ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent)) {
                                frames[$0] = $1
                            },
                            size: fixture.size, insets: insets, language: language, category: category,
                            scale: fixture.scale)
                        defer { host.close() }
                        try await host.settle()
                        let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
                        let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                            host.window.bounds.inset(by: insets))
                        let toggle = try XCTUnwrap(frames[sent ? .backToSignIn : .submit])
                        let maximum = max(
                            -scroll.adjustedContentInset.top,
                            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        let needed = max(0, toggle.maxY - viewport.maxY + AuthTokens.fieldGap)
                        let context =
                            "\(alias), \(language), \(category), sent=\(sent), viewport=\(viewport), maximumOffset=\(maximum)"
                        XCTAssertGreaterThanOrEqual(maximum, scroll.contentOffset.y + needed, context)
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: maximum), animated: false)
                        try await host.settle()
                        let revealed = try XCTUnwrap(frames[sent ? .backToSignIn : .submit])
                        XCTAssertTrue(viewport.contains(revealed), "Last control \(revealed) outside \(context)")
                        XCTAssertLessThanOrEqual(revealed.maxY + AuthTokens.fieldGap, viewport.maxY, context)
                    }
                }
            }
        }
    }

    @MainActor func testFormAndSentStatesRespectEveryProfilesSafeInsetsAndTouchTargets() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for sent in [false, true] {
                        for state in sent ? [.none] : ForgotPasswordSnapshotState.allCases {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent, state: state)) {
                                    frames[$0] = $1
                                }, size: fixture.size, insets: fixture.insets, language: language, category: category,
                                scale: fixture.scale)
                            defer { host.close() }
                            try await host.settle()
                            XCTAssertEqual(
                                Set(frames.keys),
                                Set([AuthElement.brand, .heading, .subtitle, .card]).union(
                                    sent ? [.notice, .openEmail, .backToSignIn] : [.email, .submit]))
                            let brand = try XCTUnwrap(frames[.brand])
                            XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                            for frame in frames.values {
                                XCTAssertGreaterThan(frame.height, 0)
                                XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                                XCTAssertLessThanOrEqual(
                                    frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                            }
                            for element in sent ? [AuthElement.openEmail, .backToSignIn] : [.email, .submit] {
                                XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[element]).height, AuthTokens.touch)
                            }
                            XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                            let first = try XCTUnwrap(frames[sent ? .notice : .email])
                            let second = try XCTUnwrap(frames[sent ? .openEmail : .submit])
                            XCTAssertLessThanOrEqual(first.maxY, second.minY)

                        }
                    }
                }
            }
        }
    }
}

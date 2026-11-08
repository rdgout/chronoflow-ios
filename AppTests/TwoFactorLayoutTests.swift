import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class TwoFactorLayoutTests: XCTestCase {
    @MainActor func testLastControlCanScrollAboveKeyboardInsetsOnDuoAndSE() async throws {
        try await AuthTestHost.registerFonts()
        // Duo's saved visible keyboard begins at 414 of 678 points; SE's keyboard is 218 points tall.
        for (alias, keyboardInset) in [("duo", CGFloat(264)), ("se", CGFloat(218))] {
            let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == alias })
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for recovery in [false, true] {
                        var frames: [AuthElement: CGRect] = [:]
                        var insets = fixture.insets
                        insets.bottom = max(insets.bottom, keyboardInset)
                        let host = try AuthTestHost(
                            TwoFactorView(model: twoFactorSnapshotModel(recovery: recovery)) { frames[$0] = $1 },
                            size: fixture.size, insets: insets, language: language, category: category,
                            scale: fixture.scale)
                        defer { host.close() }
                        try await host.settle()
                        let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
                        let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                            host.window.bounds.inset(by: insets))
                        let toggle = try XCTUnwrap(frames[.modeToggle])
                        let maximum = max(
                            -scroll.adjustedContentInset.top,
                            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        let needed = max(0, toggle.maxY - viewport.maxY + AuthTokens.fieldGap)
                        let context =
                            "\(alias), \(language), \(category), recovery=\(recovery), viewport=\(viewport), maximumOffset=\(maximum)"
                        XCTAssertGreaterThanOrEqual(maximum, scroll.contentOffset.y + needed, context)
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: maximum), animated: false)
                        try await host.settle()
                        let revealed = try XCTUnwrap(frames[.modeToggle])
                        XCTAssertTrue(viewport.contains(revealed), "Last control \(revealed) outside \(context)")
                        XCTAssertLessThanOrEqual(revealed.maxY + AuthTokens.fieldGap, viewport.maxY, context)
                    }
                }
            }
        }
    }

    @MainActor func testModesAndErrorsRespectEveryProfilesSafeInsetsAndTouchTargets() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for recovery in [false, true] {
                        for state in TwoFactorSnapshotState.allCases {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                TwoFactorView(model: twoFactorSnapshotModel(recovery: recovery, state: state)) {
                                    frames[$0] = $1
                                }, size: fixture.size, insets: fixture.insets, language: language, category: category,
                                scale: fixture.scale)
                            defer { host.close() }
                            try await host.settle()
                            XCTAssertEqual(
                                Set(frames.keys), [.brand, .heading, .subtitle, .card, .code, .submit, .modeToggle])
                            let brand = try XCTUnwrap(frames[.brand])
                            XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                            for frame in frames.values {
                                XCTAssertGreaterThan(frame.height, 0)
                                XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                                XCTAssertLessThanOrEqual(
                                    frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                            }
                            for element in [AuthElement.code, .submit, .modeToggle] {
                                XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[element]).height, AuthTokens.touch)
                            }
                            XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                            XCTAssertLessThanOrEqual(
                                try XCTUnwrap(frames[.code]).maxY, try XCTUnwrap(frames[.submit]).minY)
                            XCTAssertLessThanOrEqual(
                                try XCTUnwrap(frames[.submit]).maxY, try XCTUnwrap(frames[.modeToggle]).minY)
                        }
                    }
                }
            }
        }
    }
}

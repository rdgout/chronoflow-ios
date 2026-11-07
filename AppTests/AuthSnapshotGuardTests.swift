import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSnapshotGuardTests: XCTestCase {
    @MainActor func testEveryControlCanBeCapturedWithoutClippingAfterScrolling() async throws {
        try await FontRegistry.register()
        let duo = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "duo" })
        let asymmetric = AuthDeviceFixture(
            name: "duo-asymmetric", size: duo.size,
            insets: UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 62), scale: duo.scale)
        for fixture in try AuthDeviceFixture.all() + [asymmetric] {
            for language in ["en", "nl"] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                        for mode in 0..<9 {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
                            defer { host.close() }
                            if mode == 0 {
                                host.configure(
                                    SignInView(
                                        model: authSnapshotModel(), back: {}, guest: {}, measure: { frames[$0] = $1 }),
                                    style: style, language: language, category: category)
                            } else if mode < 3 {
                                host.configure(
                                    TwoFactorView(
                                        model: twoFactorSnapshotModel(recovery: mode == 2), measure: { frames[$0] = $1 }
                                    ),
                                    style: style, language: language, category: category)
                            }
                            if mode >= 3 {
                                host.configure(
                                    ForgotPasswordView(
                                        model: await forgotPasswordSnapshotModel(
                                            sent: mode == 8,
                                            state: mode == 8 ? .none : ForgotPasswordSnapshotState.allCases[mode - 3]),
                                        measure: { frames[$0] = $1 }),
                                    style: style, language: language, category: category)
                            }
                            try await host.settle()
                            let scroll = try XCTUnwrap(scrollViews(host.controller.view).first)
                            let elements: [AuthElement] =
                                mode == 0
                                ? [.brand, .passkey, .email, .password, .submit, .forgot, .signup, .footer]
                                : mode < 3
                                    ? [.brand, .code, .submit, .modeToggle]
                                    : mode < 8
                                        ? [.brand, .email, .submit] : [.brand, .notice, .openEmail, .backToSignIn]
                            for element in elements {
                                let frame = try XCTUnwrap(frames[element])
                                let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                                    host.window.bounds.inset(by: fixture.insets))
                                let delta =
                                    frame.minY < viewport.minY
                                    ? frame.minY - viewport.minY : max(0, frame.maxY - viewport.maxY)
                                let maximum = max(
                                    -scroll.adjustedContentInset.top,
                                    scroll.contentSize.height - scroll.bounds.height
                                        + scroll.adjustedContentInset.bottom)
                                let offset = min(
                                    maximum, max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + delta))
                                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                                try await host.settle()
                                let actual = try XCTUnwrap(frames[element])
                                XCTAssertTrue(
                                    viewport.insetBy(dx: -1 / host.scale, dy: -1 / host.scale).contains(actual),
                                    "\(fixture.name), \(language), \(style), \(category), mode \(mode), \(element): \(actual) outside \(viewport)"
                                )
                                let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                                XCTAssertTrue(
                                    AuthSnapshotCapture.hasInk(raster, in: actual, scale: host.scale),
                                    "Blank \(element) in \(actual), \(fixture.name), \(language), \(style), \(category)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor private func scrollViews(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}

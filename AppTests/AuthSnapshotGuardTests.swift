import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSnapshotGuardTests: XCTestCase {
    @MainActor func testSignInControls() async throws { try await checkAuthCapture(mode: 0) }
}

nonisolated final class TwoFactorCodeSnapshotGuardTests: XCTestCase {
    @MainActor func testCodeControls() async throws { try await checkAuthCapture(mode: 1) }
}

nonisolated final class TwoFactorRecoverySnapshotGuardTests: XCTestCase {
    @MainActor func testRecoveryControls() async throws { try await checkAuthCapture(mode: 2) }
}

nonisolated final class ForgotFormSnapshotGuardTests: XCTestCase {
    @MainActor func testFormControls() async throws { try await checkAuthCapture(mode: 3) }
}

nonisolated final class ForgotFieldSnapshotGuardTests: XCTestCase {
    @MainActor func testFieldErrorControls() async throws { try await checkAuthCapture(mode: 4) }
}

nonisolated final class ForgotThrottleSnapshotGuardTests: XCTestCase {
    @MainActor func testThrottleControls() async throws { try await checkAuthCapture(mode: 5) }
}

nonisolated final class ForgotServerSnapshotGuardTests: XCTestCase {
    @MainActor func testServerControls() async throws { try await checkAuthCapture(mode: 6) }
}

nonisolated final class ForgotOfflineSnapshotGuardTests: XCTestCase {
    @MainActor func testOfflineControls() async throws { try await checkAuthCapture(mode: 7) }
}

nonisolated final class ForgotSentSnapshotGuardTests: XCTestCase {
    @MainActor func testSentControls() async throws { try await checkAuthCapture(mode: 8) }
}

@MainActor private func checkAuthCapture(mode: Int) async throws {
    try await AuthTestHost.registerFonts()
    for fixture in try AuthDeviceFixture.layoutStressProfiles() {
        for language in ["en", "nl"] {
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
            defer { host.close() }
            let measure: (AuthElement, CGRect) -> Void = { frames[$0] = $1 }
            if mode == 0 {
                host.configure(
                    SignInView(model: authSnapshotModel(), back: {}, guest: {}, measure: measure),
                    language: language, category: .extraExtraLarge)
            } else if mode < 3 {
                host.configure(
                    TwoFactorView(model: twoFactorSnapshotModel(recovery: mode == 2), measure: measure),
                    language: language, category: .extraExtraLarge)
            } else {
                host.configure(
                    ForgotPasswordView(
                        model: await forgotPasswordSnapshotModel(
                            sent: mode == 8,
                            state: mode == 8 ? .none : ForgotPasswordSnapshotState.allCases[mode - 3]),
                        measure: measure), language: language, category: .extraExtraLarge)
            }
            try await host.settle()
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                host.window.bounds.inset(by: fixture.insets))
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(
                minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let elements: [AuthElement] =
                mode == 0
                ? [.brand, .passkey, .email, .password, .submit, .forgot, .signup, .footer]
                : mode < 3
                    ? [.brand, .code, .submit, .modeToggle]
                    : mode < 8 ? [.brand, .email, .submit] : [.brand, .notice, .openEmail, .backToSignIn]
            let initialOffset = scroll.contentOffset.y
            let initialFrames = frames
            let tolerance = viewport.insetBy(dx: -1 / host.scale, dy: -1 / host.scale)
            for element in elements {
                let frame = try XCTUnwrap(initialFrames[element])
                XCTAssertTrue(
                    ScrollReachability.reveal(
                        frame, viewport: tolerance, currentOffset: initialOffset,
                        minimumOffset: minimum, maximumOffset: maximum
                    ).fits,
                    "Unreachable \(element): \(frame), \(fixture.name), \(language)")
            }
            var remaining = Set(elements)
            // Endpoints cover most controls together; capture an interior position only if needed.
            var offsets = maximum == initialOffset ? [initialOffset] : [initialOffset, maximum]
            while let offset = offsets.first {
                offsets.removeFirst()
                if scroll.contentOffset.y != offset {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                    try await host.settle()
                }
                let raster = try SnapshotRaster(image: XCTUnwrap(host.image().cgImage))
                for element in remaining {
                    let actual = try XCTUnwrap(frames[element])
                    if tolerance.contains(actual) {
                        XCTAssertTrue(
                            AuthSnapshotCapture.hasInk(raster, in: actual, scale: host.scale),
                            "Blank \(element): \(actual), \(fixture.name), \(language)")
                        remaining.remove(element)
                    }
                }
                if offsets.isEmpty, let element = remaining.sorted(by: { $0.rawValue < $1.rawValue }).first {
                    let result = ScrollReachability.reveal(
                        try XCTUnwrap(frames[element]), viewport: viewport,
                        currentOffset: scroll.contentOffset.y, minimumOffset: minimum, maximumOffset: maximum)
                    guard result.fits, result.offset != scroll.contentOffset.y else {
                        XCTFail("Cannot capture \(element): \(fixture.name), \(language)")
                        break
                    }
                    offsets.append(result.offset)
                }
            }
            XCTAssertTrue(remaining.isEmpty, "Uncaptured controls: \(remaining)")
        }
    }
}

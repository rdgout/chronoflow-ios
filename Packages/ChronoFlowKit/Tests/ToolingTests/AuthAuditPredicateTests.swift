import CoreGraphics
import XCTest

nonisolated final class AuthAuditPredicateTests: XCTestCase {
    func testSignUpFooterExceptionRequiresItsOwnFrameAndPassingPixels() {
        let button = CGRect(x: 16, y: 700, width: 358, height: 48)
        XCTAssertTrue(
            AuthAuditPolicy.isMeasuredSignUpBackContrast(
                identifier: "sign-up.back", frame: button, backFrame: button, isContrast: true, minimum: 4.5))
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: button, backFrame: button, isContrast: true, minimum: minimum
                ))
        }
        for identifier: String? in [nil, "", "sign-up.submit", "auth.subtitle", "sign-up.back.new"] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSignUpBackContrast(
                    identifier: identifier, frame: button, backFrame: button, isContrast: true, minimum: 10))
        }
        for frame: CGRect? in [nil, .zero, .null, .infinite, button.offsetBy(dx: 0, dy: 20)] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: frame, backFrame: button, isContrast: true, minimum: 10))
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSignUpBackContrast(
                    identifier: "sign-up.back", frame: button, backFrame: frame, isContrast: true, minimum: 10))
        }
        XCTAssertFalse(
            AuthAuditPolicy.isMeasuredSignUpBackContrast(
                identifier: "sign-up.back", frame: button, backFrame: button, isContrast: false, minimum: 10))
    }

    func testDisabledExceptionRequiresOnlyContrastAndAnExplicitDisabledState() {
        XCTAssertTrue(AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: false))
        for enabled: Bool? in [nil, true] {
            XCTAssertFalse(AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: enabled))
        }
        XCTAssertFalse(AuthAuditPolicy.isDisabledContrast(isContrast: false, isEnabled: false))
    }

    func testWordmarkExceptionRequiresItsOwnGeometryAndPassingPixels() {
        let brand = CGRect(x: 130, y: 63, width: 140, height: 24)
        let wordmark = CGRect(x: 158, y: 62.999999, width: 112.000001, height: 24.000002)
        for identifier: String? in [nil, ""] {
            XCTAssertTrue(
                AuthAuditPolicy.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, isContrast: true, minimum: 4.5))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: brand, isContrast: true, minimum: minimum))
        }
        for frame: CGRect? in [nil, .zero, .null, .infinite, wordmark.offsetBy(dx: 0, dy: 1)] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredBrandContrast(
                    identifier: nil, frame: frame, brandFrame: brand, isContrast: true, minimum: 15))
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredBrandContrast(
                    identifier: nil, frame: wordmark, brandFrame: frame, isContrast: true, minimum: 15))
        }
        for identifier in ["auth.brand", "auth.banner", "sign-up.submit", "auth.subtitle"] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredBrandContrast(
                    identifier: identifier, frame: wordmark, brandFrame: brand, isContrast: true, minimum: 15))
        }
        XCTAssertFalse(
            AuthAuditPolicy.isMeasuredBrandContrast(
                identifier: nil, frame: wordmark, brandFrame: brand, isContrast: false, minimum: 15))
    }

    func testOnlyClippedScheduledControlContrastCanWaitForItsReveal() {
        let viewport = CGRect(x: 0, y: 47, width: 390, height: 500)
        let button = CGRect(x: 36, y: 530, width: 318, height: 44)
        XCTAssertTrue(
            AuthAuditPolicy.isDeferredControlContrast(
                isContrast: true, frame: button, viewport: viewport, controlFrames: [button]))
        for frame: CGRect? in [nil, .zero, .null, .infinite, button.offsetBy(dx: 0, dy: 50)] {
            XCTAssertFalse(
                AuthAuditPolicy.isDeferredControlContrast(
                    isContrast: true, frame: frame, viewport: viewport, controlFrames: [button]))
        }
        XCTAssertFalse(
            AuthAuditPolicy.isDeferredControlContrast(
                isContrast: true, frame: button, viewport: viewport, controlFrames: []))
        XCTAssertFalse(
            AuthAuditPolicy.isDeferredControlContrast(
                isContrast: true, frame: button, viewport: viewport.insetBy(dx: 0, dy: -100),
                controlFrames: [button]))
        XCTAssertFalse(
            AuthAuditPolicy.isDeferredControlContrast(
                isContrast: false, frame: button, viewport: viewport, controlFrames: [button]))
    }

    func testBannerExceptionRequiresMatchingGeometryAndPassingPixels() {
        let banner = CGRect(x: 30, y: 300, width: 330, height: 64)
        let title = CGRect(x: 78, y: 312, width: 262, height: 20)
        for state in ["server", "throttle"] {
            for identifier: String? in [nil, "", "auth.banner"] {
                for frame in [banner, title] {
                    XCTAssertTrue(
                        AuthAuditPolicy.isMeasuredForgotBannerContrast(
                            identifier: identifier, frame: frame, bannerFrame: banner,
                            isContrast: true, state: state, minimum: 4.5))
                }
            }
        }
        for frame in [title.offsetBy(dx: 0, dy: 100), CGRect(x: 158, y: 63, width: 112, height: 24)] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: frame, bannerFrame: banner,
                    isContrast: true, state: "server", minimum: 14.884))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    isContrast: true, state: "server", minimum: minimum))
        }
        for state: String? in [nil, "form", "sent", "field", "offline", "sign-in"] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredForgotBannerContrast(
                    identifier: nil, frame: title, bannerFrame: banner,
                    isContrast: true, state: state, minimum: 10))
        }
        for identifier in ["auth.banner.new", "auth.back", "forgot.email", "forgot.submit", "auth.subtitle"] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredForgotBannerContrast(
                    identifier: identifier, frame: title, bannerFrame: banner,
                    isContrast: true, state: "server", minimum: 10))
        }
        for invalid: CGRect? in [
            nil, .zero, .null, .infinite, CGRect(x: 30, y: 270, width: 330, height: 40),
            CGRect(x: 40, y: 100, width: 44, height: 44),
        ] {
            for identifier: String? in [nil, "", "auth.banner"] {
                XCTAssertFalse(
                    AuthAuditPolicy.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: invalid, bannerFrame: banner,
                        isContrast: true, state: "server", minimum: 10))
                XCTAssertFalse(
                    AuthAuditPolicy.isMeasuredForgotBannerContrast(
                        identifier: identifier, frame: title, bannerFrame: invalid,
                        isContrast: true, state: "server", minimum: 10))
            }
        }
        XCTAssertFalse(
            AuthAuditPolicy.isMeasuredForgotBannerContrast(
                identifier: nil, frame: title, bannerFrame: banner,
                isContrast: false, state: "server", minimum: 10))
    }

    func testAuditAllowsOnlyTheGuestFooterBoardContrastPair() {
        XCTAssertTrue(AuthAuditPolicy.isBoardContrast(identifier: "sign-in.guest", isContrast: true))
        XCTAssertFalse(AuthAuditPolicy.isBoardContrast(identifier: "sign-in.guest", isContrast: false))
        for identifier in [
            nil, "", "sign-in", "sign-in.submit", "sign-in.passkey", "sign-in.email", "sign-in.password",
            "sign-in.forgot", "sign-in.signup", "two-factor.code", "two-factor.recovery_code",
            "two-factor.submit", "two-factor.toggle", "forgot.email", "forgot.submit", "forgot.notice",
            "forgot.open-email", "forgot.back", "auth.back", "auth.heading", "auth.banner", "welcome.plan",
            "sign-in.guest.new", "auth.subtitle",
        ] {
            XCTAssertFalse(AuthAuditPolicy.isBoardContrast(identifier: identifier, isContrast: true))
        }
    }

    func testSubtitleExceptionRequiresAnExactContrastIssueAndAMeasuredPassingMinimum() {
        for minimum in [4.5, 10.8] {
            XCTAssertTrue(
                AuthAuditPolicy.isMeasuredSubtitleContrast(
                    identifier: "auth.subtitle", isContrast: true, minimum: minimum))
        }
        for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSubtitleContrast(
                    identifier: "auth.subtitle", isContrast: true, minimum: minimum))
        }
        for identifier in [nil, "", "auth.subtitle.new", "auth.heading", "two-factor.toggle", "sign-in.submit"] {
            XCTAssertFalse(
                AuthAuditPolicy.isMeasuredSubtitleContrast(identifier: identifier, isContrast: true, minimum: 10.8))
        }
        XCTAssertFalse(
            AuthAuditPolicy.isMeasuredSubtitleContrast(
                identifier: "auth.subtitle", isContrast: false, minimum: 10.8))
    }

}

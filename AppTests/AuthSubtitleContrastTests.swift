import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSubtitleContrastTests: XCTestCase {
    @MainActor func testSignInSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 0) }
    @MainActor func testTwoFactorCodeSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 1) }
    @MainActor func testTwoFactorRecoverySubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 2) }
    @MainActor func testForgotFormSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 3) }
    @MainActor func testForgotFieldSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 4) }
    @MainActor func testForgotThrottleSubtitleAndBannerAtEveryAuditRevealPosition() async throws {
        try await check(mode: 5)
    }
    @MainActor func testForgotServerSubtitleAndBannerAtEveryAuditRevealPosition() async throws {
        try await check(mode: 6)
    }
    @MainActor func testForgotOfflineSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 7) }
    @MainActor func testForgotSentSubtitleAtEveryAuditRevealPosition() async throws { try await check(mode: 8) }

    @MainActor private func check(mode: Int) async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "17e" })
        for (style, language, category) in fixture.authSnapshotVariants {
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
            } else {
                host.configure(
                    ForgotPasswordView(
                        model: await forgotPasswordSnapshotModel(
                            sent: mode == 8,
                            state: mode == 8 ? .none : ForgotPasswordSnapshotState.allCases[mode - 3]),
                        measure: { frames[$0] = $1 }),
                    style: style, language: language, category: category)
            }
            try await host.settle()
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            let viewport = host.window.bounds.inset(by: fixture.insets)
            let sky = CfSkyLayer()
            sky.frame = host.window.bounds
            sky.appearance = style == .dark ? .dark : .light
            let format = UIGraphicsImageRendererFormat()
            format.scale = host.scale
            format.preferredRange = .standard
            let skyImage = UIGraphicsImageRenderer(size: fixture.size, format: format).image {
                sky.render(in: $0.cgContext)
            }
            let expectedSky = try SnapshotRaster(image: XCTUnwrap(skyImage.cgImage))
            let targets: [AuthElement] =
                mode == 0
                ? [.brand, .passkey, .email, .password, .submit, .forgot, .signup, .footer]
                : mode < 3
                    ? [.brand, .code, .submit, .modeToggle]
                    : mode < 8
                        ? [.brand, .email, .submit] : [.brand, .notice, .openEmail, .backToSignIn]
            var measuredOffsets: Set<CGFloat> = []
            for target in targets {
                let frame = try XCTUnwrap(frames[target])
                let delta =
                    frame.minY < viewport.minY
                    ? frame.minY - viewport.minY : max(0, frame.maxY - viewport.maxY)
                let maximum = max(
                    -scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height
                        + scroll.adjustedContentInset.bottom)
                let offset = min(
                    maximum, max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + delta))
                guard measuredOffsets.insert(offset).inserted else { continue }
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                try await host.settle()
                let subtitle = try XCTUnwrap(frames[.subtitle])
                let raster = try SnapshotRaster(png: XCTUnwrap(host.image().pngData()))
                let color = UIColor(ColorToken.skyTitle.color).resolvedColor(
                    with: host.controller.traitCollection)
                let rgb = try XCTUnwrap(
                    color.cgColor.converted(
                        to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric,
                        options: nil)?.components)
                let font = Typography.authBody.uiFont(compatibleWith: host.controller.traitCollection)
                let lineHeight =
                    try XCTUnwrap(Typography.authBody.lineHeight) * font.pointSize
                    / Typography.authBody.size
                let measurement = RenderedTextContrast.measure(
                    raster: raster, frame: subtitle, scale: host.scale, lineHeight: lineHeight,
                    text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
                let lines = measurement.lines
                let visible = subtitle.intersection(viewport)
                if !visible.isNull && !visible.isEmpty {
                    let difference = try XCTUnwrap(
                        RenderedTextContrast.maximumBackgroundDifference(
                            raster: raster, reference: expectedSky, frame: subtitle, scale: host.scale,
                            text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport),
                        "No clean background across subtitle columns")
                    XCTAssertLessThanOrEqual(
                        difference, 2, "Sky must use the board ramp behind the subtitle: \(subtitle)")
                }
                if mode == 5 || mode == 6 {
                    let card = try XCTUnwrap(frames[.card])
                    let email = try XCTUnwrap(frames[.email])
                    let banner = CGRect(
                        x: card.minX + AuthTokens.cardPadding,
                        y: card.minY + AuthTokens.cardPadding,
                        width: card.width - 2 * AuthTokens.cardPadding,
                        height: email.minY - card.minY - AuthTokens.cardPadding - AuthTokens.cardGap)
                    var textFrame = banner.insetBy(
                        dx: AuthTokens.bannerHorizontal, dy: AuthTokens.bannerVertical)
                    let glyph = AuthTokens.bannerGlyph + AuthTokens.bannerGap
                    textFrame.origin.x += glyph
                    textFrame.size.width -= glyph
                    let visible = textFrame.intersection(viewport)
                    if !visible.isEmpty, !visible.isNull {
                        let color = UIColor(ColorToken.cardForeground.color).resolvedColor(
                            with: host.controller.traitCollection)
                        let rgb = try XCTUnwrap(
                            color.cgColor.converted(
                                to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric,
                                options: nil)?.components)
                        let style = Typography.authHint
                        let font = style.uiFont(compatibleWith: host.controller.traitCollection)
                        let measurement = RenderedTextContrast.measure(
                            raster: raster, frame: textFrame, scale: host.scale,
                            lineHeight: try XCTUnwrap(style.lineHeight) * font.pointSize / style.size,
                            text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
                        let message =
                            "Forgot banner contrast [\(language), \(category), mode=\(mode), reveal=\(target), appearance=\(host.controller.traitCollection.userInterfaceStyle)]: tokens=cardForeground/authErrorBackground, frame=\(textFrame), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines), minimum=\(String(describing: measurement.minimum)):1"
                        print(message)
                        XCTAssertGreaterThanOrEqual(try XCTUnwrap(measurement.minimum, message), 4.5, message)
                    }
                }
                let context =
                    "\(fixture.name), \(language), \(style), \(category), mode=\(mode), reveal=\(target), offset=\(scroll.contentOffset.y), subtitle=\(subtitle)"
                print("Auth subtitle contrast [\(context)] visibleLines=\(lines.count)")
                if !visible.isNull && !visible.isEmpty {
                    XCTAssertNotNil(
                        measurement.minimum,
                        "Unmeasurable subtitle [\(context)], lines=\(lines.count)/\(measurement.expectedLines)"
                    )
                }
                if viewport.contains(subtitle) {
                    XCTAssertEqual(
                        lines.count, max(1, Int((subtitle.height / lineHeight).rounded())), context)
                }
                for (index, line) in lines.enumerated() {
                    let message =
                        "Auth subtitle contrast [\(context)] line=\(index + 1), frame=\(line.frame), ratio=\(line.minimum)...\(line.maximum):1, ink=\(line.ink)"
                    print(message)
                    XCTAssertGreaterThanOrEqual(line.minimum, 4.5, message)
                }
            }
        }
    }
}

@MainActor func authScrollViews(_ view: UIView) -> [UIScrollView] {
    (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(authScrollViews)
}

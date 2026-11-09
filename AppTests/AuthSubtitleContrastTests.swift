import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSubtitleContrastTests: XCTestCase {
    @MainActor func testThrottleBannerAndSubtitleAtPartialScrollReveal() async throws { try await check(mode: 5) }
    @MainActor func testServerBannerAndSubtitleAtPartialScrollReveal() async throws { try await check(mode: 6) }

    @MainActor private func check(mode: Int) async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        var insets = fixture.insets
        insets.bottom = max(insets.bottom, fixture.size.height / 2)
        let language = "nl"
        let category = UIContentSizeCategory.extraExtraLarge
        for style in [UIUserInterfaceStyle.light, .dark] {
            var frames: [AuthElement: CGRect] = [:]
            let host = try AuthTestHost(
                EmptyView(), size: fixture.size, insets: insets, scale: fixture.scale)
            defer { host.close() }
            host.configure(
                ForgotPasswordView(
                    model: await forgotPasswordSnapshotModel(state: mode == 5 ? .attempts : .server),
                    measure: { frames[$0] = $1 }), style: style, language: language, category: category)
            try await host.settleLayout { Array(frames.values) }
            try await host.settle()
            let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
            let viewport = host.window.bounds.inset(by: insets)
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
            let initialSubtitle = try XCTUnwrap(frames[.subtitle])
            let font = Typography.authBody.uiFont(compatibleWith: host.controller.traitCollection)
            let lineHeight = try XCTUnwrap(Typography.authBody.lineHeight) * font.pointSize / Typography.authBody.size
            let maximum = max(
                -scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let minimum = -scroll.adjustedContentInset.top
            let initialOffset = scroll.contentOffset.y
            let requested = initialOffset + initialSubtitle.minY - viewport.minY + lineHeight / 2
            XCTAssertGreaterThanOrEqual(maximum, requested, "Fixture must allow a partial subtitle reveal")
            let offset = min(maximum, max(minimum, requested))
            XCTAssertGreaterThan(offset, initialOffset, "Fixture must exercise scroll reveal")
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            try await host.settleLayout { Array(frames.values) }
            try await host.settle()
            // Settle and measure through the same CPU capture used by the passing reveal audits.
            let image = try host.image()
            let attachment = XCTAttachment(image: image)
            attachment.name = "forgot-contrast-\(mode)-\(style.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let subtitle = try XCTUnwrap(frames[.subtitle])
            XCTAssertEqual(scroll.contentOffset.y, offset, accuracy: 1 / host.scale)
            XCTAssertEqual(
                subtitle.minY, initialSubtitle.minY - (offset - initialOffset), accuracy: 1 / host.scale,
                "Measured subtitle must reflect the committed scroll offset")
            XCTAssertLessThan(subtitle.minY, viewport.minY, "Fixture must partially clip the subtitle")
            let raster = try SnapshotRaster(image: XCTUnwrap(image.cgImage))
            let color = UIColor(ColorToken.skyTitle.color).resolvedColor(
                with: host.controller.traitCollection)
            let rgb = try XCTUnwrap(
                color.cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric,
                    options: nil)?.components)
            let measurement = RenderedTextContrast.measure(
                raster: raster, frame: subtitle, scale: host.scale, lineHeight: lineHeight,
                text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport)
            let lines = measurement.lines
            let visible = subtitle.intersection(viewport)
            XCTAssertFalse(visible.isNull || visible.isEmpty, "Scrolled subtitle must remain visible")
            if !visible.isNull && !visible.isEmpty {
                let difference = try XCTUnwrap(
                    RenderedTextContrast.maximumBackgroundDifference(
                        raster: raster, reference: expectedSky, frame: subtitle, scale: host.scale,
                        text: Array(rgb.prefix(3)).map(Double.init), viewport: viewport),
                    "No clean background across subtitle columns")
                XCTAssertLessThanOrEqual(
                    difference, 2, "Sky must use the board ramp behind the subtitle: \(subtitle)")
            }
            do {
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
                XCTAssertFalse(visible.isNull || visible.isEmpty, "Scrolled banner must remain visible")
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
                        "Forgot banner contrast [\(language), \(category), mode=\(mode), reveal=partial, appearance=\(host.controller.traitCollection.userInterfaceStyle)]: tokens=cardForeground/authErrorBackground, frame=\(textFrame), measuredLines=\(measurement.lines.count)/\(measurement.expectedLines), minimum=\(String(describing: measurement.minimum)):1"
                    print(message)
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(measurement.minimum, message), 4.5, message)
                }
            }
            let context =
                "\(fixture.name), \(language), \(style), \(category), mode=\(mode), reveal=partial, offset=\(scroll.contentOffset.y), subtitle=\(subtitle)"
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

@MainActor func authScrollViews(_ view: UIView) -> [UIScrollView] {
    (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(authScrollViews)
}

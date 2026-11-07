import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class AuthSubtitleContrastTests: XCTestCase {
    @MainActor func testRenderedSubtitleLinesAtEveryAuditRevealPosition() async throws {
        try await FontRegistry.register()
        for fixture in try AuthDeviceFixture.all() where ["board", "17e"].contains(fixture.name) {
            for language in ["en", "nl"] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                        for mode in 0..<3 {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
                            defer { host.close() }
                            if mode == 0 {
                                host.configure(
                                    SignInView(
                                        model: authSnapshotModel(), back: {}, guest: {}, measure: { frames[$0] = $1 }),
                                    style: style, language: language, category: category)
                            } else {
                                host.configure(
                                    TwoFactorView(
                                        model: twoFactorSnapshotModel(recovery: mode == 2), measure: { frames[$0] = $1 }
                                    ),
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
                                : [.brand, .code, .submit, .modeToggle]
                            for target in targets {
                                let frame = try XCTUnwrap(frames[target])
                                let delta =
                                    frame.minY < viewport.minY
                                    ? frame.minY - viewport.minY : max(0, frame.maxY - viewport.maxY)
                                let maximum = max(
                                    -scroll.adjustedContentInset.top,
                                    scroll.contentSize.height - scroll.bounds.height
                                        + scroll.adjustedContentInset.bottom)
                                scroll.setContentOffset(
                                    CGPoint(
                                        x: scroll.contentOffset.x,
                                        y: min(
                                            maximum,
                                            max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + delta))),
                                    animated: false)
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
                                    for y in Int(visible.minY * host.scale)..<Int(visible.maxY * host.scale) {
                                        for channel in 0..<3 {
                                            let pixel = y * raster.width * 4 + channel
                                            XCTAssertLessThanOrEqual(
                                                abs(Int(raster.bytes[pixel]) - Int(expectedSky.bytes[pixel])), 2,
                                                "Sky must use the board ramp over the full window, row \(y)")
                                        }
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
            }
        }
    }
}

@MainActor func authScrollViews(_ view: UIView) -> [UIScrollView] {
    (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(authScrollViews)
}

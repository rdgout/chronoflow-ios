import CoreGraphics
import Foundation
import SnapshotSupport
import Testing

@testable import DesignSystem

#if canImport(UIKit)
    import UIKit
#endif

struct PlanLayoutEvidenceTests {
    @Test func nativeCloseAuditFixtureHasPassingTextDespiteItsLowContrastGlassBoundary() throws {
        let url = try #require(
            Bundle.module.url(forResource: "native-close", withExtension: "png", subdirectory: "PlanAudit"))
        let raster = try SnapshotRaster(png: Data(contentsOf: url))
        let frame = CGRect(x: 0, y: 0, width: raster.width, height: raster.height)
        let measurement = RenderedTextContrast.measure(
            raster: raster, frame: frame, scale: 1, lineHeight: frame.height,
            text: [0, 0, 0], viewport: frame)
        let minimum = try #require(measurement.minimum)
        #expect(abs(minimum - 19.713437351795424) < 0.001)
        #expect(
            PlanLayoutEvidence.passingText(
                issueIdentifier: "legend.close", issueFrame: frame, identifier: "legend.close", frame: frame,
                minimum: minimum))
        #expect(
            !PlanLayoutEvidence.passingText(
                issueIdentifier: "legend.close.new", issueFrame: frame, identifier: "legend.close", frame: frame,
                minimum: minimum))
        #expect(
            !PlanLayoutEvidence.passingText(
                issueIdentifier: "legend.close", issueFrame: frame.offsetBy(dx: 0, dy: frame.height),
                identifier: "legend.close", frame: frame, minimum: minimum))
    }

    @Test @MainActor func planFontsScaleThroughTheRootCap() async throws {
        try await FontRegistry.register()
        let styles: [Typography.Style] = [
            Typography.screenHero, Typography.screenPageTitle, Typography.screenCardTitle,
            Typography.screenSectionTitle, Typography.screenDayTitle,
            Typography.screenBodyLg, Typography.screenBody, Typography.screenLabel, Typography.screenMeta,
            Typography.screenEyebrow, Typography.screenBlockLabel,
            Typography.screenPriorityTag,
        ]
        for style in styles {
            #expect(style.relativeTo != nil)
            #if canImport(UIKit)
                let normal = style.uiFont(compatibleWith: .init(preferredContentSizeCategory: .large))
                let capped = style.uiFont(compatibleWith: .init(preferredContentSizeCategory: .extraExtraLarge))
                let above = style.uiFont(
                    compatibleWith: .init(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
                #expect(capped.pointSize > normal.pointSize)
                #expect(above.pointSize == capped.pointSize)
            #endif
        }
    }

    @Test func planTextPairsPassAAInBothAppearancesIncludingDimmedCompletedCards() throws {
        let pairs: [(ColorToken, [ColorToken])] = [
            (.foreground, [.background, .card, .surface2]),
            (.mutedForeground, [.background, .card, .surface2]),
            (.dawnText, [.card, .surface2]), (.dawnForeground, [.dawn]),
            (.secondaryForeground, [.secondary]), (.primaryForeground, [.primary]),
        ]
        for appearance in TokenAppearance.allCases {
            func rgb(_ token: ColorToken) throws -> [Double] {
                let color = token.components(for: appearance).cgColor
                let components = try #require(
                    color.converted(
                        to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .relativeColorimetric, options: nil)?
                        .components)
                return Array(components.prefix(3)).map(Double.init)
            }
            let background = try rgb(.background)
            let completed: [(ColorToken, [ColorToken])] = [
                (.foreground, [.card]), (.mutedForeground, [.card]), (.secondaryForeground, [.secondary]),
            ]
            for (variants, opacity) in [(pairs, 1.0), (completed, PlanUITokens.completedCardOpacity)] {
                for (ink, surfaces) in variants {
                    for surface in surfaces {
                        let text = try zip(rgb(ink), background).map { $0 * opacity + $1 * (1 - opacity) }
                        let fill = try zip(rgb(surface), background).map { $0 * opacity + $1 * (1 - opacity) }
                        let ratio = RenderedTextContrast.ratio(text, fill)
                        #expect(ratio >= 4.5, "\(ink)/\(surface) \(appearance) opacity=\(opacity): \(ratio):1")
                    }
                }
            }
        }
    }

    @Test func viewportUsesEveryProfileInsetWithoutClippingAwayAnUnsafeRail() throws {
        for device in try SnapshotDevice.all() {
            let window = CGRect(origin: .zero, size: device.size)
            let insets = device.insets
            let viewport = PlanLayoutEvidence.contentViewport(
                scroll: window, top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
            #expect(viewport.minX == insets.left)
            #expect(viewport.maxX == window.maxX - insets.right)
            #expect(viewport.minY == insets.top)
            #expect(viewport.maxY == window.maxY - insets.bottom)
            if insets.right > 0 {
                let ignoredRail = PlanLayoutEvidence.contentViewport(
                    scroll: window, top: insets.top, left: insets.left, bottom: insets.bottom, right: 0)
                #expect(ignoredRail.maxX > viewport.maxX)
            }
            let reversed = PlanLayoutEvidence.contentViewport(
                scroll: window, top: insets.bottom, left: insets.right, bottom: insets.top, right: insets.left)
            #expect(reversed.minX == insets.right)
            #expect(reversed.maxX == window.maxX - insets.left)
        }
    }

    @Test func textExceptionRequiresPassingPixelsAndMatchingIdentityAndGeometry() {
        let identifier = "plan.text.mutedForeground.CFFigtree-Regular.14.0"
        let frame = CGRect(x: 36, y: 300, width: 220, height: 20)
        for issueIdentifier: String? in [nil, "", identifier] {
            #expect(
                PlanLayoutEvidence.passingText(
                    issueIdentifier: issueIdentifier, issueFrame: frame, identifier: identifier, frame: frame,
                    minimum: 4.5))
            for minimum: Double? in [nil, 4.499, .nan, .infinity, -.infinity] {
                #expect(
                    !PlanLayoutEvidence.passingText(
                        issueIdentifier: issueIdentifier, issueFrame: frame, identifier: identifier,
                        frame: frame, minimum: minimum))
            }
            for invalid: CGRect? in [nil, .zero, .null, .infinite, frame.offsetBy(dx: 0, dy: 40)] {
                #expect(
                    !PlanLayoutEvidence.passingText(
                        issueIdentifier: issueIdentifier, issueFrame: invalid, identifier: identifier,
                        frame: frame, minimum: 10))
            }
        }
        for wrong in ["today.trip", "today.progress", identifier + ".other"] {
            #expect(
                !PlanLayoutEvidence.passingText(
                    issueIdentifier: wrong, issueFrame: frame, identifier: identifier, frame: frame, minimum: 10))
        }
        #expect(
            !PlanLayoutEvidence.passingText(
                issueIdentifier: "today.trip", issueFrame: frame, identifier: "today.trip", frame: frame, minimum: 10))
    }
}

import CoreText
import DesignSystem
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class ContentSizeCapTests: XCTestCase {
    @MainActor
    func testEveryLargerCategoryClampsAndSmallerCategoriesArePreserved() {
        for category: UIContentSizeCategory in [
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
        ] {
            XCTAssertEqual(ContentSizeCap.clamp(category), .extraExtraLarge)
        }
        for category: UIContentSizeCategory in [.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge] {
            XCTAssertEqual(ContentSizeCap.clamp(category), category)
        }
    }

    @MainActor
    func testAX5FontsFallbackRowAndRenderedStatusEqualXXLarge() async throws {
        try await FontRegistry.register()
        let normal = UITraitCollection(preferredContentSizeCategory: .large)
        let capped = UITraitCollection(preferredContentSizeCategory: .extraExtraLarge)
        let largest = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        for style in [
            Typography.status, Typography.welcomeWordmark, Typography.eyebrow, Typography.headline, Typography.copy,
            Typography.primaryButton, Typography.secondaryButton,
        ] {
            let font = style.uiFont(compatibleWith: capped)
            XCTAssertEqual(style.uiFont(compatibleWith: largest).pointSize, font.pointSize)
            XCTAssertLessThan(style.uiFont(compatibleWith: normal).pointSize, font.pointSize)
        }
        let row = LaunchArguments.fallbackRowHeight(compatibleWith: capped)
        XCTAssertEqual(LaunchArguments.fallbackRowHeight(compatibleWith: largest), row)
        XCTAssertLessThan(LaunchArguments.fallbackRowHeight(compatibleWith: normal), row)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        func status(_ category: UIContentSizeCategory) throws -> (CGFloat, CGRect, [UInt8]) {
            let traits = scene.traitCollection.modifyingTraits {
                $0.preferredContentSizeCategory = category
                $0.displayScale = scene.screen.scale
                $0.userInterfaceStyle = .light
            }
            let launch = LaunchScene(size: scene.coordinateSpace.bounds.size, traits: traits, reduceMotion: false)
            launch.prepareStatus()
            let label = try XCTUnwrap(launch.statusLine.text)
            let attributed = try XCTUnwrap(label.string as? NSAttributedString)
            let font = try XCTUnwrap(
                attributed.attribute(
                    NSAttributedString.Key(kCTFontAttributeName as String), at: 0, effectiveRange: nil) as! CTFont?)
            let format = UIGraphicsImageRendererFormat()
            format.scale = scene.screen.scale
            let image = UIGraphicsImageRenderer(size: launch.statusLine.bounds.size, format: format).image { context in
                launch.statusLine.render(in: context.cgContext)
            }
            return (CTFontGetSize(font), label.frame, pixels(image))
        }
        let xxLarge = try status(.extraExtraLarge)
        let ax5 = try status(.accessibilityExtraExtraExtraLarge)
        let large = try status(.large)
        XCTAssertEqual(xxLarge.0, ax5.0)
        XCTAssertEqual(xxLarge.1, ax5.1)
        XCTAssertEqual(xxLarge.2, ax5.2)
        XCTAssertLessThan(large.0, xxLarge.0)
        XCTAssertNotEqual(large.1, xxLarge.1)
    }

    @MainActor
    func testBothProductionWindowsSetTheCap() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.keyWindow
        let delegate = SceneDelegate()
        defer {
            delegate.sceneDidDisconnect(scene)
            previousKey?.makeKey()
        }
        delegate.connect(
            to: scene, firstConnection: true, arguments: LaunchArguments(["-cf.mode", "welcome", "-cf.freezeAt", "0"]))
        let deadline = ContinuousClock.now + .seconds(5)
        while delegate.window == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try XCTUnwrap(delegate.window).maximumContentSizeCategory, .extraExtraLarge)
        XCTAssertEqual(try XCTUnwrap(delegate.overlayWindow).maximumContentSizeCategory, .extraExtraLarge)
    }
}

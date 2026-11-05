import Launch
import UIKit
import XCTest

nonisolated final class LaunchFrameParityTests: XCTestCase {
    @MainActor
    func testWholeFrameMatchesStoryboardInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let storyboard = try LaunchTestHost.storyboardController()
            let referenceHost = try LaunchTestHost(controller: storyboard, style: style)
            defer { referenceHost.close() }
            let referenceView = try XCTUnwrap(storyboard.view)
            let controller = UIViewController()
            let frameView = LaunchFrameView(traits: referenceView.traitCollection)
            controller.view = frameView
            let frameHost = try LaunchTestHost(controller: controller, style: style)
            defer { frameHost.close() }

            XCTAssertEqual(frameView.bounds, referenceView.bounds)
            let scale = referenceHost.window.traitCollection.displayScale
            let reference = try LaunchTestHost.pixels(of: referenceView, scale: scale)
            let frame = try LaunchTestHost.pixels(of: frameView, scale: scale)
            LaunchTestHost.assertPixelsEqual(
                frame, reference, width: Int((frameView.bounds.width * scale).rounded()),
                style: style, context: "Whole-frame")
            var isOpaque = true
            var hasMoon = false
            for pixel in stride(from: 0, to: frame.count, by: 4) {
                isOpaque = isOpaque && frame[pixel + 3] == 255
                hasMoon = hasMoon || (0..<3).contains { abs(Int(frame[pixel + $0]) - Int(frame[$0])) > 2 }
            }
            XCTAssertTrue(isOpaque)
            XCTAssertTrue(hasMoon)
            assertStaticTree(frameView.layer)

            let referenceMoon = try LaunchTestHost.moon(in: referenceView)
            let moon = try LaunchTestHost.moon(in: frameView)
            let traits = LaunchTestHost.imageTraits(style: style, scale: scale)
            let expected = try XCTUnwrap(UIImage(named: "LaunchMoon", in: .main, compatibleWith: traits))
            for imageView in [referenceMoon, moon] {
                try LaunchTestHost.assertMoonImage(imageView, matches: expected, traits: traits)
                LaunchTestHost.assertPixelsEqual(
                    try LaunchTestHost.pixels(of: imageView, scale: scale),
                    try LaunchTestHost.pixels(of: expected, traits: traits),
                    width: Int((expected.size.width * scale).rounded()), style: style, context: "Rendered parity moon")
            }
            XCTAssertEqual(moon.bounds.size, referenceMoon.bounds.size)
            XCTAssertEqual(moon.frame.midX, referenceMoon.frame.midX, accuracy: 0.5)
            XCTAssertEqual(moon.frame.midY, referenceMoon.frame.midY, accuracy: 0.5)
        }
    }

    @MainActor
    func testNaturalSizeAndPixelAlignmentSurviveResizingAndAsymmetricInsets() throws {
        let controller = UIViewController()
        let host = try LaunchTestHost(controller: controller, style: .dark)
        defer { host.close() }
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 17, left: 53, bottom: 31, right: 23)
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        let view = LaunchFrameView(frame: controller.view.bounds, traits: controller.traitCollection)
        controller.view.addSubview(view)
        let moon = try LaunchTestHost.moon(in: view)
        let image = try XCTUnwrap(moon.image)
        let scale = host.window.traitCollection.displayScale
        let windowSize = host.window.bounds.size
        for size in [
            windowSize,
            CGSize(width: windowSize.width - 1 / scale, height: windowSize.height - 3 / scale),
            CGSize(width: windowSize.width + 2 / scale, height: windowSize.height + 1 / scale),
        ] {
            view.frame = CGRect(origin: .zero, size: size)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            XCTAssertEqual(moon.bounds.size, image.size)
            XCTAssertEqual(moon.frame.midX, view.bounds.midX, accuracy: 0.5)
            XCTAssertEqual(moon.frame.midY, view.bounds.midY, accuracy: 0.5)
            XCTAssertEqual(moon.frame.minX * scale, (moon.frame.minX * scale).rounded(), accuracy: 0.001)
            XCTAssertEqual(moon.frame.minY * scale, (moon.frame.minY * scale).rounded(), accuracy: 0.001)
            XCTAssertFalse(view.hasAmbiguousLayout)
            XCTAssertFalse(moon.hasAmbiguousLayout)
            assertStaticTree(view.layer)
        }
    }

    @MainActor
    func testAppearanceIsCapturedForTheDurationOfTheSplash() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let controller = UIViewController()
            let host = try LaunchTestHost(controller: controller, style: style)
            defer { host.close() }
            let frame = LaunchFrameView(frame: controller.view.bounds, traits: controller.traitCollection)
            controller.view.addSubview(frame)
            frame.layoutIfNeeded()
            let scale = host.window.traitCollection.displayScale
            let original = try LaunchTestHost.pixels(of: frame, scale: scale)
            host.window.overrideUserInterfaceStyle = style == .dark ? .light : .dark
            host.window.layoutIfNeeded()
            frame.layoutIfNeeded()
            XCTAssertEqual(frame.traitCollection.userInterfaceStyle, style)
            XCTAssertTrue(try LaunchTestHost.pixels(of: frame, scale: scale).elementsEqual(original))
        }
    }

    @MainActor
    private func assertStaticTree(_ layer: CALayer) {
        XCTAssertNil(layer.mask)
        XCTAssertTrue(layer.filters?.isEmpty ?? true)
        XCTAssertNil(layer.compositingFilter)
        XCTAssertEqual(layer.shadowOpacity, 0)
        XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
        for child in layer.sublayers ?? [] { assertStaticTree(child) }
    }
}

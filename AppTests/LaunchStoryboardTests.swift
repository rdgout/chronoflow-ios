import UIKit
import XCTest

nonisolated final class LaunchStoryboardTests: XCTestCase {
    @MainActor
    func testMoonIsCentredInTheWholeWindowInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let controller = try LaunchTestHost.storyboardController()
            let host = try LaunchTestHost(controller: controller, style: style)
            defer { host.close() }
            let view = try XCTUnwrap(controller.view)
            let moon = try LaunchTestHost.moon(in: view)
            let scale = host.window.traitCollection.displayScale
            let traits = LaunchTestHost.imageTraits(style: style, scale: scale)
            let asset = try XCTUnwrap(
                UIImage(named: "LaunchMoon", in: .main, compatibleWith: traits)?.imageAsset)
            let expected = asset.image(with: traits)
            XCTAssertEqual(view.bounds.size, host.window.bounds.size)
            XCTAssertEqual(moon.contentMode, .center)
            XCTAssertEqual(expected.size, CGSize(width: 288, height: 288))

            let expectedPixels = try LaunchTestHost.pixels(of: expected, traits: traits)
            for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 13, left: 47, bottom: 29, right: 19)] {
                controller.additionalSafeAreaInsets = insets
                host.window.layoutIfNeeded()
                view.layoutIfNeeded()
                assertGeometry(moon, naturalSize: expected.size, in: host.window)
                XCTAssertFalse(view.hasAmbiguousLayout)
                XCTAssertFalse(moon.hasAmbiguousLayout)
                try LaunchTestHost.assertMoonImage(moon, matches: expected, traits: traits)

                let actualPixels = try LaunchTestHost.pixels(of: moon, scale: scale)
                LaunchTestHost.assertPixelsEqual(
                    actualPixels, expectedPixels, width: Int((expected.size.width * scale).rounded()),
                    style: style, context: "Rendered moon, safe-area insets \(insets)")
            }

            let sky = try XCTUnwrap(UIColor(named: "LaunchSky", in: .main, compatibleWith: view.traitCollection))
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
            let actual = try XCTUnwrap(view.backgroundColor)
            let components = try [actual, sky].map { color in
                try XCTUnwrap(
                    color.resolvedColor(with: view.traitCollection).cgColor
                        .converted(to: colorSpace, intent: .defaultIntent, options: nil)?.components)
            }
            XCTAssertEqual(components[0].count, 4)
            XCTAssertEqual(components[1].count, 4)
            for (component, expected) in zip(components[0], components[1]) {
                XCTAssertEqual(component, expected, accuracy: 1 / 255.0)
            }
        }
    }

    @MainActor
    private func assertGeometry(_ moon: UIImageView, naturalSize: CGSize, in window: UIWindow) {
        let frame = moon.convert(moon.bounds, to: window)
        XCTAssertEqual(frame.midX, window.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, window.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(frame.size, naturalSize)
        XCTAssertTrue(window.bounds.contains(frame))
        let scale = window.traitCollection.displayScale
        for edge in [frame.minX, frame.minY, frame.maxX, frame.maxY] {
            XCTAssertEqual(edge * scale, (edge * scale).rounded(), accuracy: 0.001)
        }
    }
}

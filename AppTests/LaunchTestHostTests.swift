import UIKit
import XCTest

nonisolated final class LaunchTestHostTests: XCTestCase {
    @MainActor
    func testReferenceBitmapUsesExplicitAppearanceAndScaleDespiteOppositeAmbientTraits() throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        let scale = host.window.traitCollection.displayScale
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = LaunchTestHost.imageTraits(style: style, scale: scale)
            let opposite = LaunchTestHost.imageTraits(style: style == .dark ? .light : .dark, scale: scale)
            let asset = try XCTUnwrap(
                UIImage(named: "LaunchMoon", in: .main, compatibleWith: opposite)?.imageAsset)
            let expected = asset.image(with: traits)
            XCTAssertEqual(expected.scale, scale)
            let fixed = UIImage(
                cgImage: try XCTUnwrap(expected.cgImage), scale: expected.scale,
                orientation: expected.imageOrientation)
            let expectedPixels = try LaunchTestHost.pixels(of: fixed, traits: traits)
            let oppositePixels = try LaunchTestHost.pixels(of: asset.image(with: opposite), traits: opposite)
            let difference = LaunchTestHost.pixelDifference(
                oppositePixels, expectedPixels, width: Int(expected.size.width * scale))
            XCTAssertGreaterThan(difference.maximum, 2)
            XCTAssertNotNil(difference.firstMismatch)

            var result: Result<[UInt8], any Error>?
            opposite.performAsCurrent {
                result = Result { try LaunchTestHost.pixels(of: asset.image(with: opposite), traits: traits) }
            }
            LaunchTestHost.assertPixelsEqual(
                try XCTUnwrap(result).get(), expectedPixels, width: Int(expected.size.width * scale),
                style: style, context: "Reference under opposite ambient appearance")
        }
    }

}

nonisolated final class RasterPixelLogicTests: XCTestCase {
    @MainActor
    func testPixelDifferenceReportsFirstMismatchCoordinatesAndWorstChannel() {
        let expected = [UInt8](repeating: 0, count: 2 * 2 * 4)
        var actual = expected
        actual[0] = 2
        let tolerated = LaunchTestHost.pixelDifference(actual, expected, width: 2)
        XCTAssertEqual(tolerated.maximum, 2)
        XCTAssertNil(tolerated.firstMismatch)

        actual[10] = 3
        actual[15] = 41
        let difference = LaunchTestHost.pixelDifference(actual, expected, width: 2)
        XCTAssertEqual(difference.maximum, 41)
        XCTAssertEqual(difference.firstMismatch, "(x: 0, y: 1), channel B, actual 3, expected 0")
    }
}

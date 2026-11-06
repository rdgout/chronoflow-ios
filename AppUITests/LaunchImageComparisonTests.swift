import CoreGraphics
import XCTest

extension LaunchSceneTests {
    func testOnePointOffsetsAndWrongOpacityAreRejectedAtBothDisplayScales() {
        for scale in [2, 3] {
            let width = 80 * scale
            let region = CGRect(x: 0, y: 0, width: width, height: width)
            func fixture(dx: Int = 0, dy: Int = 0, opacity: Double = 1) -> [UInt8] {
                var bytes = [UInt8](repeating: 0, count: width * width * 4)
                for y in 0..<width {
                    for x in 0..<width {
                        let inside =
                            (20 * scale + dx..<60 * scale + dx).contains(x)
                            && (20 * scale + dy..<60 * scale + dy).contains(y)
                        for channel in 0..<3 {
                            bytes[(y * width + x) * 4 + channel] = inside ? UInt8(200 * opacity) : 40
                        }
                        bytes[(y * width + x) * 4 + 3] = 255
                    }
                }
                return bytes
            }
            let expected = fixture()
            XCTAssertTrue(LaunchImageComparison.measure(expected, expected, width: width, region: region).passes)
            for (dx, dy) in [(scale, 0), (0, scale), (-scale, -scale)] {
                let actual = fixture(dx: dx, dy: dy)
                let metrics = LaunchImageComparison.measure(actual, expected, width: width, region: region)
                XCTAssertFalse(metrics.passes)
                let shift = LaunchImageComparison.bestShift(
                    actual, expected, width: width, region: region, radius: scale * 2)
                XCTAssertEqual(shift.x, dx)
                XCTAssertEqual(shift.y, dy)
            }
            let opacityError = LaunchImageComparison.measure(
                fixture(opacity: 0.8), expected, width: width, region: region)
            XCTAssertFalse(opacityError.passes)
            XCTAssertGreaterThan(opacityError.interiorMean, 1)
            var dithered = expected
            for i in dithered.indices where i % 4 != 3 { dithered[i] += UInt8(i % 2) }
            XCTAssertTrue(LaunchImageComparison.measure(dithered, expected, width: width, region: region).passes)
        }
    }
}

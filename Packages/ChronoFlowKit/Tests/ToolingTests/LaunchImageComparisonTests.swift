import CoreGraphics
import XCTest

nonisolated final class LaunchImageComparisonTests: XCTestCase {
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
    func testPrunedShiftSearchMatchesExhaustiveSearchIncludingTiesAndClampedEdges() {
        let width = 9
        let height = 7
        let region = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = 2
        for seed in 0..<5 {
            let expected = (0..<(width * height * 4)).map { UInt8(($0 * seed * 17) % 255) }
            let actual = (0..<(width * height * 4)).map { UInt8(($0 * seed * 13 + seed) % 255) }
            var exhaustive = (x: 0, y: 0)
            var minimum = Int.max
            for dy in -radius...radius {
                for dx in -radius...radius {
                    var error = 0
                    for y in 0..<height {
                        for x in 0..<width {
                            let px = min(width - 1, max(0, x + dx))
                            let py = min(height - 1, max(0, y + dy))
                            for channel in 0..<3 {
                                error += abs(
                                    Int(actual[(py * width + px) * 4 + channel])
                                        - Int(expected[(y * width + x) * 4 + channel]))
                            }
                        }
                    }
                    if error < minimum
                        || (error == minimum && abs(dx) + abs(dy) < abs(exhaustive.x) + abs(exhaustive.y))
                    {
                        minimum = error
                        exhaustive = (dx, dy)
                    }
                }
            }
            let actualShift = LaunchImageComparison.bestShift(
                actual, expected, width: width, region: region, radius: radius)
            XCTAssertEqual(actualShift.x, exhaustive.x)
            XCTAssertEqual(actualShift.y, exhaustive.y)
        }
    }

}

import CoreGraphics
import Foundation

nonisolated enum LaunchImageComparison {
    struct Metrics {
        let mean: Double
        let fraction: Double
        let interiorMean: Double
        let interiorFraction: Double

        var passes: Bool { mean <= 1 && fraction <= 0.005 && interiorMean <= 1 && interiorFraction <= 0.005 }
        var description: String {
            "sRGB mean \(mean), >8/255 fraction \(fraction); away from edges: mean \(interiorMean), fraction \(interiorFraction)"
        }
    }

    static func measure(_ actual: [UInt8], _ expected: [UInt8], width: Int, region: CGRect) -> Metrics {
        var errorSum = 0
        var different = 0
        var count = 0
        var interiorError = 0
        var interiorDifferent = 0
        var interiorCount = 0
        let height = expected.count / (width * 4)
        var edges = [Bool](repeating: false, count: width * height)
        actual.withUnsafeBufferPointer { actualBuffer in
            expected.withUnsafeBufferPointer { expectedBuffer in
                let actual = actualBuffer.baseAddress!
                let expected = expectedBuffer.baseAddress!
                for y in max(0, Int(region.minY) - 1)..<min(height, Int(region.maxY) + 1) {
                    for x in max(0, Int(region.minX) - 1)..<min(width, Int(region.maxX) + 1) {
                        let index = (y * width + x) * 4
                        let right = (y * width + min(width - 1, x + 1)) * 4
                        let below = (min(height - 1, y + 1) * width + x) * 4
                        var edge = false
                        for channel in 0..<3 {
                            if abs(Int(expected[index + channel]) - Int(expected[right + channel])) > 8
                                || abs(Int(expected[index + channel]) - Int(expected[below + channel])) > 8
                            {
                                edge = true
                                break
                            }
                        }
                        if edge {
                            for py in max(0, y - 1)...min(height - 1, y + 1) {
                                for px in max(0, x - 1)...min(width - 1, x + 1) { edges[py * width + px] = true }
                            }
                        }
                    }
                }
                for y in Int(region.minY)..<Int(region.maxY) {
                    for x in Int(region.minX)..<Int(region.maxX) {
                        let edge = edges[y * width + x]
                        for channel in 0..<3 {
                            let index = (y * width + x) * 4 + channel
                            let error = abs(Int(expected[index]) - Int(actual[index]))
                            errorSum += error
                            different += error > 8 ? 1 : 0
                            count += 1
                            if !edge {
                                interiorError += error
                                interiorDifferent += error > 8 ? 1 : 0
                                interiorCount += 1
                            }
                        }
                    }
                }
            }
        }
        return Metrics(
            mean: Double(errorSum) / Double(max(1, count)), fraction: Double(different) / Double(max(1, count)),
            interiorMean: Double(interiorError) / Double(max(1, interiorCount)),
            interiorFraction: Double(interiorDifferent) / Double(max(1, interiorCount)))
    }

    static func bestShift(
        _ actual: [UInt8], _ expected: [UInt8], width: Int, region: CGRect, radius: Int
    ) -> (x: Int, y: Int) {
        let height = expected.count / (width * 4)
        var best = (x: 0, y: 0)
        var minimum = Int.max
        actual.withUnsafeBufferPointer { actualBuffer in
            expected.withUnsafeBufferPointer { expectedBuffer in
                let actual = actualBuffer.baseAddress!
                let expected = expectedBuffer.baseAddress!
                func error(dx: Int, dy: Int, limit: Int) -> Int {
                    var sum = 0
                    var y = Int(region.minY)
                    while y < Int(region.maxY) {
                        let py = min(height - 1, max(0, y + dy))
                        var x = Int(region.minX)
                        while x < Int(region.maxX) {
                            let px = min(width - 1, max(0, x + dx))
                            let actualIndex = (py * width + px) * 4
                            let expectedIndex = (y * width + x) * 4
                            sum += abs(Int(actual[actualIndex]) - Int(expected[expectedIndex]))
                            sum += abs(Int(actual[actualIndex + 1]) - Int(expected[expectedIndex + 1]))
                            sum += abs(Int(actual[actualIndex + 2]) - Int(expected[expectedIndex + 2]))
                            if sum > limit { return sum }
                            x += 1
                        }
                        y += 1
                    }
                    return sum
                }
                minimum = error(dx: 0, dy: 0, limit: .max)
                if minimum == 0 { return }
                for dy in -radius...radius {
                    for dx in -radius...radius where dx != 0 || dy != 0 {
                        let error = error(dx: dx, dy: dy, limit: minimum)
                        if error < minimum || (error == minimum && abs(dx) + abs(dy) < abs(best.x) + abs(best.y)) {
                            minimum = error
                            best = (dx, dy)
                        }
                    }
                }
            }
        }
        return best
    }
}

import CoreGraphics
import DesignSystem
import Foundation
import Testing

@testable import Launch

struct LaunchGlowTests {
    @Test func gaussianDiscAndClippedHalo() {
        let expected = (1 - exp(-6 * 6 / (2 * 5 * 5))) * 0.8
        #expect(abs(LaunchPaint.planeAlphas[0] - expected) < 0.0001)
        #expect(LaunchPaint.planeAlphas.count == 49)
        #expect(
            zip(LaunchPaint.planeAlphas, LaunchPaint.planeAlphas.dropFirst()).allSatisfy {
                $0 >= $1 && $1 >= 0
            })
        let halo = LaunchGlow.haloStops.dropFirst(2).map(\.1)
        #expect(zip(halo, halo.dropFirst()).allSatisfy { $0 >= $1 && $1 >= 0 })
        #expect(LaunchGlow.haloStops.allSatisfy { (0...0.45).contains($0.1) })
        #expect(LaunchGlow.haloStops.filter { $0.0 <= 90 / 250 }.allSatisfy { $0.1 == 0 })
        #expect(LaunchGlow.haloStops.contains { $0.1 > 0.1 })
        #expect(LaunchGlow.haloStops.last?.1 == 0)
    }

    @Test func planeIsBakedAtBothDisplayScales() throws {
        for scale: CGFloat in [2, 3] {
            let image = LaunchGlow.plane(color: LaunchPaint.white.cgColor, scale: scale)
            #expect(image.width == Int(48 * scale))
            #expect(image.height == image.width)
            let bytes = try #require(image.dataProvider?.data) as Data
            let alpha = { (x: Int, y: Int) in bytes[y * image.bytesPerRow + x * 4 + 3] }
            #expect(alpha(Int(24 * scale), Int(24 * scale)) == 255)
            #expect(alpha(Int(30 * scale), Int(24 * scale)) > 0)
            #expect(alpha(0, 0) == 0)
        }
    }
}

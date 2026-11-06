import Launch
import UIKit
import XCTest

nonisolated final class LaunchImageMutationTests: XCTestCase {
    @MainActor func testSampledMoonRejectsOffsetAndWrongOpacity() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for scale: CGFloat in [2, 3] {
                let size = CGSize(width: 390, height: 844)
                let scene = LaunchScene(
                    size: size,
                    traits: UITraitCollection {
                        $0.userInterfaceStyle = style
                        $0.displayScale = scale
                    }, reduceMotion: false)
                let values = scene.timeline.sample(at: .milliseconds(700))
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                func render() throws -> [UInt8] {
                    let image = UIGraphicsImageRenderer(size: size, format: format).image {
                        scene.container.render(in: $0.cgContext)
                    }
                    return pixels(image)
                }
                scene.apply(values)
                let reference = try render()
                let moon = scene.layer(.moon)
                let region = CGRect(
                    x: (moon.position.x - 56) * scale, y: (moon.position.y - 56) * scale, width: 112 * scale,
                    height: 112 * scale
                ).integral
                for key in ["position", "opacity"] {
                    scene.apply(values)
                    if key == "position" { moon.position.x += 1 } else { moon.opacity *= 0.8 }
                    let actual = try render()
                    let metrics = LaunchImageComparison.measure(
                        actual, reference, width: Int(size.width * scale), region: region)
                    XCTAssertFalse(metrics.passes)
                    if key == "opacity" { XCTAssertGreaterThan(metrics.mean, 1) }
                    if key == "position" {
                        let shift = LaunchImageComparison.bestShift(
                            actual, reference, width: Int(size.width * scale), region: region,
                            radius: Int(ceil(1.5 * scale)))
                        XCTAssertEqual(CGFloat(shift.x) / scale, 1, accuracy: 0.5 / scale)
                    }
                }
            }
        }
    }
}

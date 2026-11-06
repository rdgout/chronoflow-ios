import DesignSystem
import Launch
import UIKit
import XCTest

nonisolated final class LaunchSceneTests: XCTestCase {
    @MainActor
    func testOpeningAccessibilityAndFrozenScreenshotMatchesSampleAt700() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cf.mode", "ready", "-cf.freezeAt", "700"]
        app.launch()
        let opening = app.images["launch.opening"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10))
        XCTAssertFalse(opening.label.isEmpty)
        let screenshot = opening.screenshot()
        let actual = try XCTUnwrap(screenshot.image.cgImage)
        let size = opening.frame.size
        let scale = CGFloat(actual.width) / size.width
        let actualBytes = try pixels(actual)
        let statusBar = app.statusBars.firstMatch
        let top = statusBar.exists ? max(0, statusBar.frame.maxY - opening.frame.minY) : 0
        var errors: [(metrics: LaunchImageComparison.Metrics, moon: LaunchImageComparison.Metrics, shift: CGFloat)] = []
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection {
                $0.userInterfaceStyle = style
                $0.displayScale = scale
            }
            let scene = LaunchScene(size: size, traits: traits, reduceMotion: false)
            scene.apply(scene.timeline.withReadyExit(at: .milliseconds(1500)).sample(at: .milliseconds(700)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let model = UIGraphicsImageRenderer(size: size, format: format).image { context in
                scene.container.render(in: context.cgContext)
            }
            let expected = try pixels(XCTUnwrap(model.cgImage))
            XCTAssertEqual(expected.count, actualBytes.count)
            guard expected.count == actualBytes.count else { return }
            let region = CGRect(
                x: 0, y: ceil(top * scale), width: CGFloat(actual.width),
                height: CGFloat(actual.height) - ceil(top * scale))
            let metrics = LaunchImageComparison.measure(actualBytes, expected, width: actual.width, region: region)
            let moon = scene.layer(.moon)
            let moonRegion = CGRect(
                x: (moon.position.x - 56) * scale, y: (moon.position.y - 56) * scale,
                width: 112 * scale, height: 112 * scale
            ).integral
            let shift = LaunchImageComparison.bestShift(
                actualBytes, expected, width: actual.width, region: moonRegion, radius: Int(ceil(1.5 * scale)))
            let displacement = CGFloat(max(abs(shift.x), abs(shift.y))) / scale
            let moonMetrics = LaunchImageComparison.measure(
                actualBytes, expected, width: actual.width, region: moonRegion)
            errors.append((metrics, moonMetrics, displacement))
            if style == .light {
                let reference = scene.timeline.sample(at: .milliseconds(700))
                for key in ["position", "opacity"] {
                    scene.apply(reference)
                    if key == "position" { moon.position.x += 1 } else { moon.opacity *= 0.8 }
                    let mutant = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        scene.container.render(in: context.cgContext)
                    }
                    let mutantBytes = try pixels(XCTUnwrap(mutant.cgImage))
                    let mutation = LaunchImageComparison.measure(
                        mutantBytes, expected, width: actual.width, region: moonRegion)
                    XCTAssertFalse(
                        mutation.passes, "The real sampled moon must reject a 1 pt offset or 20% opacity error: \(key)")
                    if key == "opacity" {
                        XCTAssertGreaterThan(
                            mutation.mean, 1, "The actual moon-region mean assertion must reject wrong opacity")
                    }
                    if key == "position" {
                        let offset = LaunchImageComparison.bestShift(
                            mutantBytes, expected, width: actual.width, region: moonRegion,
                            radius: Int(ceil(1.5 * scale)))
                        XCTAssertEqual(CGFloat(offset.x) / scale, 1, accuracy: 0.5 / scale)
                    }
                }
            }
            let attachment = XCTAttachment(image: model)
            attachment.name = "sample-700-\(style == .dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let best = try XCTUnwrap(errors.min { $0.metrics.mean < $1.metrics.mean })
        XCTAssertTrue(best.metrics.passes, best.metrics.description)
        XCTAssertLessThanOrEqual(best.moon.mean, 1, "Moon: \(best.moon.description)")
        XCTAssertLessThanOrEqual(best.moon.interiorMean, 1, "Moon away from edges: \(best.moon.description)")
        XCTAssertLessThanOrEqual(best.shift, 0.5, "Best moon alignment shift in points; a 1 pt displacement must fail")
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "live-frozen-700"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

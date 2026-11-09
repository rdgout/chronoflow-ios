import DesignSystem
import Launch
import UIKit
import XCTest

nonisolated final class LaunchSceneTests: XCTestCase {
    @MainActor
    func testLightOpeningAccessibilityAndFrozenScreenshotMatchesSampleAt700() async throws {
        try await Self.assertFrozenScreenshot(style: .light, testCase: self)
    }

    @MainActor
    fileprivate static func assertFrozenScreenshot(style expectedStyle: UIUserInterfaceStyle, testCase: XCTestCase)
        async throws
    {
        let app = XCUIApplication()
        let original = XCUIDevice.shared.appearance
        testCase.addTeardownBlock { @MainActor in
            app.terminate()
            try DeviceAppearance.set(original)
        }
        app.terminate()
        try DeviceAppearance.set(expectedStyle == .dark ? .dark : .light)
        app.launchArguments = [
            "-cf.mode", "ready", "-cf.freezeAt", "700",
        ]
        app.launchMeasured()
        let opening = app.images["launch.opening"]
        XCTAssertTrue(opening.waitUntil(.exists, timeout: 10))
        XCTAssertEqual(opening.label, "ChronoFlow is opening")
        XCTAssertEqual(opening.frame, app.frame)
        let screenshot = opening.screenshot()
        let actual = try XCTUnwrap(screenshot.image.cgImage)
        let size = opening.frame.size
        let scale = CGFloat(actual.width) / size.width
        let actualBytes = try pixels(actual)
        let statusBar = app.statusBars.firstMatch
        let top = statusBar.exists ? max(0, statusBar.frame.maxY - opening.frame.minY) : 0
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
            if style == expectedStyle {
                let shift = LaunchImageComparison.bestShift(
                    actualBytes, expected, width: actual.width, region: moonRegion, radius: Int(ceil(1.5 * scale)))
                let displacement = CGFloat(max(abs(shift.x), abs(shift.y))) / scale
                let moonMetrics = LaunchImageComparison.measure(
                    actualBytes, expected, width: actual.width, region: moonRegion)
                XCTAssertTrue(metrics.passes, metrics.description)
                XCTAssertLessThanOrEqual(moonMetrics.mean, 1, "Moon: \(moonMetrics.description)")
                XCTAssertLessThanOrEqual(
                    moonMetrics.interiorMean, 1, "Moon away from edges: \(moonMetrics.description)")
                XCTAssertLessThanOrEqual(
                    displacement, 0.5, "Best moon alignment shift in points; a 1 pt displacement must fail")
            } else {
                XCTAssertFalse(metrics.passes, "The opposite appearance must fail parity")
                XCTAssertGreaterThan(
                    metrics.mean, 8, "The opposite appearance must differ clearly: \(metrics.description)")
            }
            let attachment = XCTAttachment(image: model)
            attachment.name = "sample-700-\(style == .dark ? "dark" : "light")"
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "live-frozen-700"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    @MainActor
    private static func pixels(_ image: CGImage) throws -> [UInt8] {
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

nonisolated final class LaunchSceneDarkTests: XCTestCase {
    @MainActor
    func testDarkOpeningAccessibilityAndFrozenScreenshotMatchesSampleAt700() async throws {
        try await LaunchSceneTests.assertFrozenScreenshot(style: .dark, testCase: self)
    }
}

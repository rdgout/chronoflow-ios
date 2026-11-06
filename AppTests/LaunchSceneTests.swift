import DesignSystem
import Launch
import UIKit
import XCTest

nonisolated final class LaunchSceneTests: XCTestCase {
    @MainActor
    func testLayerOrderGeometryAndForbiddenEffects() throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let scene = LaunchScene(
                size: host.window.bounds.size,
                traits: LaunchTestHost.imageTraits(style: style, scale: host.window.screen.scale), reduceMotion: false)
            XCTAssertEqual(
                scene.container.sublayers?.compactMap(\.name),
                ["sky", "stars", "halo", "sun", "band", "path", "plane", "moon", "wordmark", "status"])
            XCTAssertEqual(Set(scene.layers.keys), Set(LayerID.allCases))
            XCTAssertTrue(scene.container.masksToBounds)
            for (actual, expected) in zip(
                [
                    scene.container.frame.minX, scene.container.frame.minY, scene.container.frame.width,
                    scene.container.frame.height,
                ],
                [host.window.bounds.minX, host.window.bounds.minY, host.window.bounds.width, host.window.bounds.height])
            {
                XCTAssertEqual(actual, expected, accuracy: 1e-9)
            }
            XCTAssertEqual(scene.container.anchorPoint, CGPoint(x: 0.5, y: 0.4))
            XCTAssertNil(scene.statusLine.text)
            XCTAssertEqual(scene.statusLine.replicator.instanceCount, 3)
            XCTAssertEqual(scene.statusLine.replicator.instanceDelay, 0.2)
            XCTAssertEqual(scene.layer(.stars).bounds.height, scene.size.height * 0.6)
            XCTAssertEqual(scene.layer(.sun).position.y, scene.size.height - 194)
            XCTAssertEqual(scene.layer(.moon).bounds.size, CGSize(width: 288, height: 288))
            XCTAssertEqual(scene.layer(.moon).minificationFilter, .trilinear)
            func check(_ layer: CALayer) {
                XCTAssertNil(layer.mask)
                XCTAssertTrue(layer.filters?.isEmpty ?? true)
                XCTAssertNil(layer.compositingFilter)
                XCTAssertEqual(layer.shadowOpacity, 0)
                XCTAssertNil(layer.shadowPath)
                XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
                layer.sublayers?.forEach(check)
            }
            check(scene.container)
        }
    }

    @MainActor
    func testFirstFrameAndReduceMotionMatchTheStoryboard() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let board = try LaunchTestHost(controller: LaunchTestHost.storyboardController(), style: style)
            defer { board.close() }
            let traits = LaunchTestHost.imageTraits(style: style, scale: board.window.screen.scale)
            let expected = try LaunchTestHost.pixels(
                of: board.window.rootViewController!.view, scale: traits.displayScale)
            for reduceMotion in [false, true] {
                let scene = LaunchScene(size: board.window.bounds.size, traits: traits, reduceMotion: reduceMotion)
                let controller = UIViewController()
                controller.view = UIView(frame: scene.container.bounds)
                controller.view.layer.addSublayer(scene.container)
                let overlay = try LaunchTestHost(controller: controller, style: style)
                defer { overlay.close() }
                let actual = try LaunchTestHost.pixels(of: controller.view, scale: traits.displayScale)
                LaunchTestHost.assertPixelsEqual(
                    actual, expected,
                    width: Int((scene.size.width * traits.displayScale).rounded()), style: style,
                    context: "CA frame zero")
            }
        }
    }

    @MainActor
    func testHaloIsTransparentInsideTheSun() throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        let scale = host.window.screen.scale
        let scene = LaunchScene(size: host.window.bounds.size, traits: host.window.traitCollection, reduceMotion: false)
        scene.apply(scene.timeline.sample(at: .milliseconds(1400)))
        let halo = scene.layer(.halo)
        halo.opacity = 1
        halo.transform = CATransform3DIdentity
        halo.position = CGPoint(x: 250, y: 250)
        let view = UIView(frame: halo.bounds)
        view.layer.addSublayer(halo)
        let pixels = try LaunchTestHost.pixels(of: view, scale: scale)
        let width = Int(500 * scale)
        func alpha(at radius: CGFloat) -> UInt8 {
            let x = Int((250 + radius) * scale)
            let y = Int(250 * scale)
            return pixels[(y * width + x) * 4 + 3]
        }
        XCTAssertEqual(alpha(at: 0), 0)
        XCTAssertEqual(alpha(at: 85), 0)
        XCTAssertGreaterThan(alpha(at: 100), 0)
    }

    @MainActor
    func testSampledScalesAreAffineAndRenderTheMoonAtItsSampledSize() throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        let traits = LaunchTestHost.imageTraits(style: .light, scale: host.window.screen.scale)
        let scene = LaunchScene(size: host.window.bounds.size, traits: traits, reduceMotion: false)
        let timeline = scene.timeline.withReadyExit(at: .milliseconds(1500))
        scene.apply(timeline.sample(at: .milliseconds(700)))
        let moon = scene.layer(.moon)
        XCTAssertTrue(CATransform3DIsAffine(moon.transform))
        XCTAssertEqual(moon.transform.m11, 0.9041499538, accuracy: 1e-9)
        let view = UIView(frame: scene.container.bounds)
        view.layer.addSublayer(moon)
        let pixels = try LaunchTestHost.pixels(of: view, scale: traits.displayScale)
        let image = LaunchImages.moon(compatibleWith: traits)
        let original = try LaunchTestHost.pixels(of: image, traits: traits)
        func inkWidth(_ pixels: [UInt8], width: Int) -> Int {
            var minX = width
            var maxX = 0
            for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 200 {
                let x = (i / 4) % width
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            return maxX - minX + 1
        }
        let renderedWidth = inkWidth(pixels, width: Int((scene.size.width * traits.displayScale).rounded()))
        let originalWidth = inkWidth(original, width: image.cgImage!.width)
        XCTAssertEqual(Double(renderedWidth), Double(originalWidth) * moon.transform.m11, accuracy: 2)
        scene.apply(timeline.sample(at: .milliseconds(1700)))
        XCTAssertTrue(CATransform3DIsAffine(scene.container.transform))
        XCTAssertGreaterThan(scene.container.transform.m11, 1)
        XCTAssertNotNil((scene.layer(.halo) as? CAGradientLayer)?.colors)
        XCTAssertNil(scene.layer(.halo).contents)
    }

    @MainActor
    func testLazyStatusAndSampledReplicas() async throws {
        try await FontRegistry.register()
        let host = try LaunchTestHost(controller: UIViewController(), style: .dark)
        defer { host.close() }
        let scene = LaunchScene(size: host.window.bounds.size, traits: host.window.traitCollection, reduceMotion: false)
        scene.prepareStatus()
        let text = try XCTUnwrap(scene.statusLine.text)
        scene.prepareStatus()
        XCTAssertTrue(scene.statusLine.text === text)
        XCTAssertNotNil(text.string)
        XCTAssertEqual(text.contentsScale, host.window.screen.scale)
        let timeline = scene.timeline.withStatus(at: .milliseconds(2000))
        let values = timeline.sample(at: .milliseconds(2600))
        scene.apply(values)
        XCTAssertEqual(scene.statusLine.opacity, 1)
        XCTAssertTrue(scene.statusLine.replicator.isHidden)
        let dots = scene.statusLine.sublayers!.filter { $0 !== text && $0 !== scene.statusLine.replicator }
        XCTAssertEqual(dots.count, 3)
        for (dot, opacity) in zip(dots, values[.statusDot]!.replicaOpacities) {
            XCTAssertFalse(dot.isHidden)
            XCTAssertEqual(Double(dot.opacity), opacity, accuracy: 0.00001)
        }
        XCTAssertGreaterThanOrEqual(text.frame.minX, 0)
        XCTAssertLessThanOrEqual(scene.statusLine.replicator.frame.maxX, scene.size.width)
    }
}

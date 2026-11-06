import AppCore
import Launch
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class LaunchPlaybackTests: XCTestCase {
    @MainActor
    func testFrozenPresentationMatchesSamplerAndRebuiltTracks() async throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            for mode in ["ready", "slow", "welcome", "reduce"] {
                let scene = LaunchScene(
                    size: host.window.bounds.size,
                    traits: LaunchTestHost.imageTraits(style: style, scale: host.window.screen.scale),
                    reduceMotion: mode == "reduce")
                host.window.rootViewController!.view.layer.addSublayer(scene.container)
                defer { scene.container.removeFromSuperlayer() }
                let safe = host.window.safeAreaInsets
                let arguments = LaunchArguments(["-cf.mode", mode == "reduce" ? "slow" : mode])
                let timeline = arguments.timeline(
                    opening: scene.timeline,
                    safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right))
                let t0 = CACurrentMediaTime()
                scene.play(scene.timeline, at: t0)
                scene.play(timeline, at: t0)
                for track in timeline.tracks where track.values.count > 1 {
                    let animation = try XCTUnwrap(
                        scene.layer(track.layer).animation(forKey: track.keyPath) as? CAKeyframeAnimation)
                    XCTAssertEqual(animation.beginTime, t0)
                    XCTAssertEqual(animation.duration, track.keyTimes.last!)
                    XCTAssertEqual(animation.fillMode, .both)
                    XCTAssertFalse(animation.isRemovedOnCompletion)
                    XCTAssertEqual(animation.keyTimes?.first, 0)
                    XCTAssertEqual(animation.keyTimes?.last, 1)
                    XCTAssertEqual(animation.timingFunctions?.count, track.curves.count)
                    XCTAssertEqual(animation.preferredFrameRateRange.preferred, 120)
                }
                for milliseconds in stride(from: 0, through: 3200, by: 100) {
                    let time = Duration.milliseconds(milliseconds)
                    scene.freeze(at: time)
                    try await Task.sleep(for: .milliseconds(25))
                    let sample = timeline.sample(at: time)
                    for track in timeline.tracks {
                        let presentation = try XCTUnwrap(
                            scene.layer(track.layer).presentation(),
                            "Missing \(mode).\(track.layer).\(track.keyPath) at \(milliseconds)")
                        let expected = try XCTUnwrap(sample[track.layer]?[track.keyPath])
                        switch expected {
                        case .scalar(let expected):
                            let actual = try XCTUnwrap(presentation.value(forKeyPath: track.keyPath) as? NSNumber)
                            XCTAssertEqual(
                                actual.doubleValue, expected, accuracy: 0.003,
                                "\(mode).\(track.layer).\(track.keyPath) at \(milliseconds)")
                        case .point(let expected):
                            let actual = try XCTUnwrap(presentation.value(forKeyPath: track.keyPath) as? NSValue)
                                .cgPointValue
                            XCTAssertEqual(actual.x, expected.x, accuracy: 0.5)
                            XCTAssertEqual(actual.y, expected.y, accuracy: 0.5)
                        }
                    }
                }
                // A target update must retain the original clock even while frozen.
                scene.play(timeline, at: t0)
                if mode != "reduce" {
                    let animation = try XCTUnwrap(scene.layer(.moon).animation(forKey: "position"))
                    XCTAssertEqual(animation.beginTime, t0)
                }
            }
        }
    }

    @MainActor
    func testBezierPresetsAgainstCoreAnimationPositionAndInteriorOpacityWithinSolverPrecision() async throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        let caSolverEpsilon = 0.0005
        for curve in [CubicBezier.linear, .easeOut, .easeInOut, .intro] {
            let layer = CALayer()
            layer.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
            host.window.rootViewController!.view.layer.addSublayer(layer)
            defer { layer.removeFromSuperlayer() }
            let t0 = CACurrentMediaTime()
            for key in ["position.x", "opacity"] {
                let animation = CAKeyframeAnimation(keyPath: key)
                animation.values = key == "opacity" ? [0.1, 0.9] : [0, 1000]
                animation.keyTimes = [0, 1]
                animation.duration = 1
                animation.beginTime = t0
                animation.timingFunctions = [
                    CAMediaTimingFunction(
                        controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2))
                ]
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: key)
            }
            layer.speed = 0
            for step in 0...20 {
                let progress = Double(step) / 20
                layer.timeOffset = t0 + progress
                CATransaction.flush()
                try await Task.sleep(for: .milliseconds(25))
                let presentation = try XCTUnwrap(layer.presentation())
                let expected = curve.value(at: progress)
                XCTAssertEqual(
                    presentation.position.x / 1000, expected, accuracy: caSolverEpsilon,
                    "Position timing for \(curve) at \(progress); tolerance allows CA's solver epsilon for a 1 s duration"
                )
                XCTAssertEqual(
                    (Double(presentation.opacity) - 0.1) / 0.8, expected, accuracy: caSolverEpsilon,
                    "Interior opacity timing for \(curve) at \(progress); tolerance allows CA's solver epsilon for a 1 s duration"
                )
            }
        }
    }

    @MainActor
    func testRemovingStatusCancelsItsAnimationAndKeepsOpening() throws {
        let host = try LaunchTestHost(controller: UIViewController(), style: .light)
        defer { host.close() }
        let scene = LaunchScene(size: host.window.bounds.size, traits: host.window.traitCollection, reduceMotion: false)
        let opening = scene.timeline
        let t0 = CACurrentMediaTime()
        scene.play(opening.withStatus(at: .seconds(2)), at: t0)
        XCTAssertNotNil(scene.layer(.statusDot).animation(forKey: "opacity"))
        scene.play(opening.withReadyExit(at: .milliseconds(1500)), at: t0)
        XCTAssertNil(scene.layer(.statusDot).animation(forKey: "opacity"))
        XCTAssertEqual(scene.layer(.status).opacity, 0)
        XCTAssertEqual(Set(scene.layer(.moon).animationKeys() ?? []), ["position", "transform.scale"])
    }
}

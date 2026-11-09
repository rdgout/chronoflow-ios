import AppCore
import DesignSystem
import Launch
import Testing
import UIKit

@Suite(.serialized) @MainActor struct LaunchSnapshotTests {
    @Test func sampledSplashFrames() async throws {
        try await FontRegistry.register()
        let start = ContinuousClock.now
        var captures = 0
        for device in try SnapshotDevice.all() {
            let profile = try device.coverage
            let host = SnapshotContainer(size: device.size, insets: device.insets, scale: device.scale)
            let controller = UIViewController()
            host.host(controller)
            defer { host.close() }
            for style in [UIUserInterfaceStyle.light, .dark] {
                var images: [String: SnapshotReference.Sample] = [:]
                for language in ["en", "nl"] {
                    for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                        let traits = UITraitCollection {
                            $0.userInterfaceStyle = style
                            $0.displayScale = device.scale
                            $0.preferredContentSizeCategory = category
                        }
                        for frame in LaunchSnapshotCase.all.filter({ profile.launchFrames.contains($0.name) }) {
                            let key = frame.name + (frame.mode == .slow ? "-\(language)-\(category.rawValue)" : "")
                            let sample: SnapshotReference.Sample
                            if let cached = images[key] {
                                sample = cached
                            } else {
                                let scene = LaunchScene(
                                    size: device.size, traits: traits, reduceMotion: frame.mode == .reduceMotion)
                                if frame.mode == .slow { scene.prepareStatus(locale: Locale(identifier: language)) }
                                scene.apply(
                                    frame.timeline(size: device.size, safeInsets: device.insets).sample(
                                        at: .milliseconds(frame.milliseconds)))
                                controller.view.layer.addSublayer(scene.container)
                                controller.view.layoutIfNeeded()
                                func display(_ layer: CALayer) {
                                    layer.displayIfNeeded()
                                    layer.sublayers?.forEach(display)
                                }
                                display(controller.view.layer)
                                CATransaction.flush()
                                #expect(
                                    (scene.container.opacity == 0)
                                        == (frame.mode == .ready && frame.milliseconds == 1900))
                                let format = UIGraphicsImageRendererFormat()
                                format.scale = device.scale
                                format.opaque = false
                                format.preferredRange = .standard
                                let image = UIGraphicsImageRenderer(size: device.size, format: format).image {
                                    controller.view.layer.render(in: $0.cgContext)
                                }
                                scene.container.removeFromSuperlayer()
                                #expect(image.cgImage?.width == Int(device.width * device.scale))
                                #expect(image.cgImage?.height == Int(device.height * device.scale))
                                if frame.mode == .slow {
                                    let text = try #require(scene.statusLine.text)
                                    let ink = text.frame.union(scene.statusLine.replicator.frame).offsetBy(
                                        dx: scene.statusLine.frame.minX, dy: scene.statusLine.frame.minY)
                                    #expect(
                                        LaunchLayout(size: device.size, safeAreaInsets: device.insets).safeBounds
                                            .contains(
                                                ink))
                                    #expect(
                                        (text.string as? NSAttributedString)?.string
                                            == (language == "nl"
                                                ? "Je plan wordt klaargezet" : "Getting your plan ready"))
                                }
                                sample = try SnapshotReference.Sample(png: #require(image.pngData()))
                                images[key] = sample
                                captures += 1
                            }
                            let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                                .appendingPathComponent("__Snapshots__/LaunchSnapshotTests")
                            let result = try verifyWelcomeSnapshot(
                                of: sample,
                                named:
                                    "\(device.name)-\(style == .dark ? "dark" : "light")-\(language)-\(category == .large ? "large" : "xxLarge")-\(frame.name)",
                                record: record, testName: "sampledSplashFrames", directory: directory,
                                content: frame.mode == .ready && frame.milliseconds == 1900
                                    ? .fullyTransparent : .visible)
                            if record {
                                #expect(result?.hasPrefix("Record mode is on.") == true, "\(result ?? "")")
                            } else {
                                #expect(result == nil, "\(result ?? "")")
                            }
                        }
                    }
                }
            }
        }
        print("sampledSplashFrames: \(captures) captures, \(start.duration(to: .now))")
    }
}

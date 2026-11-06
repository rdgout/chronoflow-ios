#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SnapshotTesting
    import Testing
    import UIKit
    @testable import Launch

    @Suite(.serialized) @MainActor struct LaunchSnapshotTests {
        @Test func sampledSplashFrames() async throws {
            try await FontRegistry.register()
            let host = SnapshotWindow()
            defer { host.close() }
            let size = host.window.bounds.size
            let scale = host.window.screen.scale
            let insets = host.insets
            let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model
            let device = "\(model)-\(Int(size.width))x\(Int(size.height))-\(Int(scale))x"
            let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection {
                    $0.userInterfaceStyle = style
                    $0.displayScale = scale
                    $0.preferredContentSizeCategory = .large
                }
                for frame in LaunchSnapshotCase.all {
                    let scene = LaunchScene(size: size, traits: traits, reduceMotion: frame.mode == .reduceMotion)
                    if frame.mode == .slow { try prepareEnglishStatus(scene) }
                    scene.apply(
                        frame.timeline(size: size, safeInsets: insets).sample(at: .milliseconds(frame.milliseconds)))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = scale
                    format.opaque = false
                    format.preferredRange = .standard
                    host.controller.view.layer.addSublayer(scene.container)
                    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        host.controller.view.layer.render(in: context.cgContext)
                    }
                    scene.container.removeFromSuperlayer()
                    #expect(image.cgImage?.width == Int((size.width * scale).rounded()))
                    #expect(image.cgImage?.height == Int((size.height * scale).rounded()))
                    let result = verifySnapshot(
                        of: image, as: .image,
                        named: "\(device)-\(style == .dark ? "dark" : "light")-\(frame.name)",
                        record: record ? .all : .never, testName: "sampledSplashFrames")
                    if record {
                        #expect(result?.hasPrefix("Record mode is on.") == true, "\(result ?? "No recording result")")
                    } else {
                        #expect(result == nil, "\(result ?? "")")
                    }
                }
            }
        }

        private func prepareEnglishStatus(_ scene: LaunchScene) throws {
            let path = try #require(Bundle.module.path(forResource: "en", ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let string = bundle.localizedString(forKey: "Getting your plan ready", value: nil, table: nil)
            #expect(string == "Getting your plan ready")
            scene.statusLine.prepareText(string)
            let text = try #require(scene.statusLine.text?.string as? NSAttributedString)
            #expect(text.string == string)
        }

        @Test func geometryInRunningWindow() async throws {
            try await FontRegistry.register()
            let host = SnapshotWindow()
            defer { host.close() }
            #expect(host.window.bounds.size == host.window.screen.bounds.size)
            for (height, statusTop, apex) in [(844.0, 518.0, 512.5), (874, 533, 542.5)] {
                let scene = LaunchScene(
                    size: CGSize(width: 390, height: height), traits: host.window.traitCollection, reduceMotion: false)
                let path = try #require(scene.layer(.path) as? CAShapeLayer)
                let pathBounds = try #require(path.path).boundingBoxOfPath
                #expect(abs(scene.statusLine.frame.minY - CGFloat(statusTop)) < 1e-9)
                #expect(abs(pathBounds.minY - CGFloat(apex)) < 0.001)
            }
            for extra in [
                UIEdgeInsets.zero,
                UIEdgeInsets(top: 7, left: 19, bottom: 11, right: 31),
                UIEdgeInsets(top: 0, left: 19, bottom: 0, right: 31),
            ] {
                host.controller.additionalSafeAreaInsets = extra
                host.window.layoutIfNeeded()
                host.controller.view.layoutIfNeeded()
                let size = host.window.bounds.size
                let insets = host.insets
                let safe = CGRect(
                    x: insets.left, y: 0, width: size.width - insets.left - insets.right, height: size.height)
                for frame in LaunchSnapshotCase.all {
                    let traits = UITraitCollection {
                        $0.userInterfaceStyle = .light
                        $0.displayScale = host.window.screen.scale
                    }
                    let scene = LaunchScene(size: size, traits: traits, reduceMotion: frame.mode == .reduceMotion)
                    try prepareEnglishStatus(scene)
                    host.controller.view.layer.addSublayer(scene.container)
                    defer { scene.container.removeFromSuperlayer() }
                    scene.apply(
                        frame.timeline(size: size, safeInsets: insets).sample(at: .milliseconds(frame.milliseconds)))
                    for id in [LayerID.moon, .wordmark, .status, .sun] {
                        let layer = scene.layer(id)
                        guard layer.opacity > 0 && scene.container.opacity > 0 else { continue }
                        let bounds: CGRect
                        switch id {
                        case .moon: bounds = layer.bounds.insetBy(dx: 92, dy: 92)
                        case .status:
                            let text = try #require(scene.statusLine.text)
                            bounds = text.frame.union(scene.statusLine.replicator.frame)
                        default: bounds = layer.bounds
                        }
                        let rect = layer.convert(bounds, to: host.controller.view.layer)
                        #expect(
                            safe.insetBy(dx: -0.5, dy: -0.5).contains(rect),
                            "\(frame.name) \(id): \(rect), horizontal safe bounds \(safe)")
                    }
                    let path = try #require(scene.layer(.path) as? CAShapeLayer)
                    let bounds = try #require(path.path).boundingBoxOfPath
                    #expect(abs(bounds.minX + 10) < 1e-9)
                    #expect(abs(bounds.maxX - size.width - 10) < 1e-9)
                    #expect(bounds.minY > 0 && bounds.maxY < size.height)
                    #expect(scene.container.masksToBounds)
                    let target = MoonTarget.fallback(size: size, safeAreaInsets: insets, rowHeight: 28)
                    #expect(safe.contains(target))
                }
            }
        }
    }

    @MainActor private final class SnapshotWindow {
        let controller = UIViewController()
        let window: UIWindow

        init() {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
            } else {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
            controller.view = UIView(frame: window.bounds)
            window.rootViewController = controller
            window.isHidden = false
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
        }

        var insets: MoonTarget.Insets {
            let value = controller.view.safeAreaInsets
            return MoonTarget.Insets(top: value.top, left: value.left, bottom: value.bottom, right: value.right)
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }
    }
#endif

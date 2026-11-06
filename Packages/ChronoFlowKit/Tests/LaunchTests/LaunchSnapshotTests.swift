#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SnapshotSupport
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
            let profile = try SnapshotProfile.current()
            let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection {
                    $0.userInterfaceStyle = style
                    $0.displayScale = scale
                    $0.preferredContentSizeCategory = .large
                }
                for frame in LaunchSnapshotCase.all.filter({ profile.launchFrames.contains($0.name) }) {
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
                    let preservesBoardReference =
                        size.height == 844 && !(frame.mode == .welcome && frame.milliseconds > 1600)
                    let recordingFrame = record && !preservesBoardReference
                    let result = verifySnapshot(
                        of: image, as: .image,
                        named: "\(device)-\(style == .dark ? "dark" : "light")-\(frame.name)",
                        record: recordingFrame ? .all : .never, testName: "sampledSplashFrames")
                    if recordingFrame {
                        #expect(result?.hasPrefix("Record mode is on.") == true, "\(result ?? "No recording result")")
                    } else {
                        #expect(result == nil, "844 pt board frames must remain unchanged: \(result ?? "")")
                    }
                }
            }
        }

        private func prepareEnglishStatus(_ scene: LaunchScene) throws {
            let path = try #require(Bundle.module.path(forResource: "en", ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let string = bundle.localizedString(forKey: "Getting your plan ready", value: nil, table: nil)
            #expect(string == "Getting your plan ready")
            scene.statusLine.prepareText(string, compatibleWith: scene.traits)
            let text = try #require(scene.statusLine.text?.string as? NSAttributedString)
            #expect(text.string == string)
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

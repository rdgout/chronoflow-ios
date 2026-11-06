#if canImport(UIKit)
    import AppCore
    import UIKit

    public final class LaunchOverlayController: UIViewController {
        public let launchScene: LaunchScene

        public init(scene: LaunchScene) {
            launchScene = scene
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { return nil }

        public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

        public override func loadView() {
            let frame = LaunchFrameView(
                frame: CGRect(origin: .zero, size: launchScene.size), traits: launchScene.traits)
            frame.install(launchScene)
            frame.isAccessibilityElement = true
            frame.accessibilityTraits = .image
            frame.accessibilityIdentifier = "launch.opening"
            frame.accessibilityLabel = String(localized: "ChronoFlow is opening", bundle: .module)
            frame.accessibilityViewIsModal = true
            view = frame
        }
    }
#endif

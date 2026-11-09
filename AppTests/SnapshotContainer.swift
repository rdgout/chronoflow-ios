import AppCore
import UIKit

@MainActor final class SnapshotContainer {
    let window: UIWindow
    let root: UIViewController
    let scale: CGFloat
    let insets: MoonTarget.Insets?
    private weak var previousKeyWindow: UIWindow?

    init(
        size: CGSize? = nil, insets: MoonTarget.Insets? = nil, scale: CGFloat? = nil,
        nativeSafeArea: Bool = false
    ) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            preconditionFailure("Snapshots require an app-hosted window scene")
        }
        previousKeyWindow = scene.keyWindow
        if nativeSafeArea, let insets {
            window = ProfileSnapshotWindow(
                scene: scene,
                insets: UIEdgeInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right))
        } else {
            window = UIWindow(windowScene: scene)
        }
        window.frame = CGRect(origin: .zero, size: size ?? scene.coordinateSpace.bounds.size)
        self.scale = scale ?? scene.screen.scale
        self.insets = insets
        root = UIViewController()
        root.traitOverrides.displayScale = self.scale
        window.rootViewController = root
    }

    func host(_ controller: UIViewController) {
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

@MainActor private final class ProfileSnapshotWindow: UIWindow {
    private let profileInsets: UIEdgeInsets

    init(scene: UIWindowScene, insets: UIEdgeInsets) {
        profileInsets = insets
        super.init(windowScene: scene)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // UIKit containers must inherit the profile's safe area instead of the executing simulator's notch.
    override var safeAreaInsets: UIEdgeInsets { profileInsets }
}

import AppCore
import DesignSystem
import Launch
import SwiftUI
import UIKit
import UserNotifications

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private(set) var overlayWindow: UIWindow?
    private(set) var overlayController: LaunchOverlayController?
    private(set) var pendingIntent = PendingLaunchIntent()
    let signposts = LaunchSignposts()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
            let app = UIApplication.shared.delegate as? AppDelegate
        else { return }
        connect(to: windowScene, firstConnection: app.launchProcess.claimOverlay())
        let response = connectionOptions.notificationResponse
        pendingIntent = PendingLaunchIntent(
            urls: Set(connectionOptions.urlContexts.map(\.url)),
            notification: response.map {
                PendingLaunchIntent.Notification(
                    requestIdentifier: $0.notification.request.identifier, actionIdentifier: $0.actionIdentifier,
                    userInfoJSON: try? JSONSerialization.data(
                        withJSONObject: $0.notification.request.content.userInfo,
                        options: .sortedKeys),
                    userText: ($0 as? UNTextInputNotificationResponse)?.userText)
            })
    }

    func connect(to windowScene: UIWindowScene, firstConnection: Bool, arguments: LaunchArguments = LaunchArguments()) {
        signposts.event(.sceneConnect)
        if firstConnection {
            signposts.begin(.launch)
            signposts.begin(.firstCommit)
            let overlay = UIWindow(windowScene: windowScene)
            let traits = windowScene.traitCollection.modifyingTraits {
                $0.displayScale = windowScene.screen.scale
            }
            let scene = LaunchScene(
                size: overlay.bounds.size, traits: traits,
                reduceMotion: arguments.reduceMotion || UIAccessibility.isReduceMotionEnabled)
            let controller = LaunchOverlayController(scene: scene)
            overlay.windowLevel = .normal + 1
            overlay.overrideUserInterfaceStyle = traits.userInterfaceStyle
            overlay.rootViewController = controller
            overlayWindow = overlay
            overlayController = controller
            overlay.isHidden = false
            controller.view.layoutIfNeeded()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let safe = controller.view.safeAreaInsets
            let timeline = arguments.timeline(
                opening: scene.timeline,
                safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right),
                rowHeight: arguments.mode == .welcome ? LaunchArguments.fallbackRowHeight(compatibleWith: traits) : 28)
            scene.play(timeline, at: CACurrentMediaTime())
            CATransaction.commit()
            CATransaction.flush()
            signposts.event(.overlayFirstCommit)
            signposts.end(.firstCommit)
            if let time = arguments.freezeAt { scene.freeze(at: time) }
            if let stall = arguments.mainThreadStall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Thread.sleep(
                        forTimeInterval: Double(stall.components.seconds) + Double(stall.components.attoseconds) / 1e18)
                }
            }
            Task {
                do {
                    try await FontRegistry.register()
                    if arguments.mode == .slow {
                        scene.prepareStatus()
                    }
                } catch { signposts.event(.fontRegistrationFailed) }
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let window = UIWindow(windowScene: windowScene)
            let controller = LaunchHostingController(rootView: RootView(), signposts: signposts)
            controller.launchIsVisible = overlayWindow != nil
            window.rootViewController = controller
            controller.view.accessibilityElementsHidden = overlayWindow != nil
            self.window = window
            window.makeKeyAndVisible()
        }
    }
}

final class LaunchHostingController<Content: View>: UIHostingController<Content> {
    var launchIsVisible = true {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }
    private let signposts: LaunchSignposts
    private var recordedLayout = false

    init(rootView: Content, signposts: LaunchSignposts) {
        self.signposts = signposts
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override var preferredStatusBarStyle: UIStatusBarStyle { launchIsVisible ? .lightContent : .default }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !recordedLayout {
            recordedLayout = true
            signposts.event(.rootFirstLayout)
        }
    }
}

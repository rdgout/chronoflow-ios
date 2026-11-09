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
    private(set) var coordinator: LaunchCoordinator?
    var navigator = RootNavigator()
    private(set) var moonAnchorStore = MoonAnchorStore()
    let signposts = LaunchSignposts()
    private var exitSignpostTask: Task<Void, Never>?
    private var introSignpostTask: Task<Void, Never>?
    private(set) var launchIntro: LaunchIntro?
    private var allowsIntro = false
    var readinessFactory: (@MainActor (LaunchArguments, any LaunchClock) -> any LaunchReadiness)?
    private var rootScheduled = false
    private var connectionGeneration = 0

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
            let app = UIApplication.shared.delegate as? AppDelegate
        else { return }
        let response = connectionOptions.notificationResponse
        pendingIntent = PendingLaunchIntent(
            urls: Set(connectionOptions.urlContexts.map(\.url)),
            notification: response.map {
                PendingLaunchIntent.Notification.capture(
                    identifier: $0.notification.request.identifier, actionIdentifier: $0.actionIdentifier,
                    userInfo: $0.notification.request.content.userInfo,
                    userText: ($0 as? UNTextInputNotificationResponse)?.userText)
            })
        navigator = app.navigator
        connect(to: windowScene, firstConnection: app.launchProcess.claimOverlay())
    }

    func connect(to windowScene: UIWindowScene, firstConnection: Bool, arguments: LaunchArguments = LaunchArguments()) {
        connectionGeneration += 1
        signposts.event(.sceneConnect)
        let diagnostic = arguments.mode != nil || arguments.freezeAt != nil
        allowsIntro = firstConnection && !(arguments.reduceMotion || UIAccessibility.isReduceMotionEnabled)
        launchIntro = nil
        moonAnchorStore = MoonAnchorStore()
        moonAnchorStore.onChange = { [weak self] frame in
            guard let self else { return }
            if diagnostic {
                if arguments.mode == .welcome { updateDiagnosticMoon(frame, arguments: arguments) }
            } else {
                coordinator?.send(.moonAnchor(frame))
            }
        }
        if firstConnection {
            signposts.begin(.launch)
            signposts.begin(.firstCommit)
            signposts.begin(.session)
            signposts.begin(.ready)
            let overlay = UIWindow(windowScene: windowScene)
            overlay.maximumContentSizeCategory = ContentSizeCap.maximumCategory
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
            controller.prepareAccessibilityLabel()
            if let time = arguments.freezeAt { scene.freeze(at: time) }
            if let stall = arguments.mainThreadStall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    Thread.sleep(
                        forTimeInterval: Double(stall.components.seconds) + Double(stall.components.attoseconds) / 1e18)
                }
            }
            Task { [weak self, weak controller] in
                do {
                    try await FontRegistry.register()
                    controller?.fontsDidRegister()
                    if arguments.mode == .slow { scene.prepareStatus() }
                } catch { self?.signposts.event(.fontRegistrationFailed) }
            }
        }
        if diagnostic || (!firstConnection && navigator.route != nil) {
            if arguments.mode == .welcome {
                navigator.navigate(to: .welcome)
                if allowsIntro {
                    launchIntro = LaunchIntro(
                        start: .milliseconds(2300),
                        clock: MediaLaunchClock(t0: overlayController?.launchScene.t0 ?? CACurrentMediaTime()),
                        frozenTime: arguments.freezeAt)
                }
            }
            mountRoot(on: windowScene)
        } else {
            startReadiness(on: windowScene, arguments: arguments)
        }
    }

    private func startReadiness(on windowScene: UIWindowScene, arguments: LaunchArguments) {
        let clock = MediaLaunchClock(t0: overlayController?.launchScene.t0 ?? CACurrentMediaTime())
        let safe = overlayController?.view.safeAreaInsets ?? windowScene.keyWindow?.safeAreaInsets ?? .zero
        let size = overlayController?.launchScene.size ?? windowScene.coordinateSpace.bounds.size
        let fallback = MoonTarget.fallback(
            size: size, safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right),
            rowHeight: LaunchArguments.fallbackRowHeight(compatibleWith: windowScene.traitCollection))
        let source =
            readinessFactory?(arguments, clock)
            ?? StubReadiness(configuration: arguments.readiness, store: KeychainSessionStore(), clock: clock)
        let coordinator = LaunchCoordinator(
            readiness: source, clock: clock,
            reduceMotion: overlayController?.launchScene.timeline.reduceMotion ?? true,
            state: .init(fallbackTarget: fallback, pendingIntent: pendingIntent)
        ) { [weak self, weak windowScene] state, effects in
            guard let self, let windowScene else { return }
            if state.session != nil { signposts.end(.session) }
            if state.isReady { signposts.end(.ready) }
            if let route = state.route {
                if route == .welcome, allowsIntro, launchIntro == nil, let start = state.exitStart {
                    launchIntro = LaunchIntro(start: start + .milliseconds(700), clock: clock)
                    scheduleIntroSignpost(clock: clock, start: start + .milliseconds(700))
                }
                navigator.navigate(to: route)
                mountRoot(on: windowScene)
            }
            if let controller = overlayController {
                controller.update(state: state, effects: effects) { [weak self] in self?.finishLaunch() }
                if state.didCommitExit, exitSignpostTask == nil, let start = state.exitStart {
                    exitSignpostTask = Task { [weak self] in
                        do { try await clock.sleep(until: start) } catch { return }
                        self?.signposts.begin(.exit)
                    }
                }
            } else if state.route != nil {
                self.coordinator?.stop()
            }
        }
        self.coordinator = coordinator
        coordinator.start()
    }

    private func mountRoot(on windowScene: UIWindowScene) {
        guard window == nil && !rootScheduled else { return }
        rootScheduled = true
        let generation = connectionGeneration
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                try? await FontRegistry.register()
                guard let self, self.connectionGeneration == generation else { return }
                let window = UIWindow(windowScene: windowScene)
                window.maximumContentSizeCategory = ContentSizeCap.maximumCategory
                let controller = LaunchHostingController(
                    rootView: RootView(
                        navigator: navigator, moonAnchorStore: moonAnchorStore, launchIntro: launchIntro,
                        forcesReduceMotion: overlayController?.launchScene.timeline.reduceMotion ?? false),
                    signposts: signposts)
                controller.launchIsVisible = overlayWindow != nil
                window.rootViewController = controller
                controller.view.accessibilityElementsHidden = overlayWindow != nil
                self.window = window
                window.makeKeyAndVisible()
            }
        }
    }

    private func scheduleIntroSignpost(clock: any LaunchClock, start: Duration) {
        introSignpostTask = Task { [weak self] in
            do {
                try await clock.sleep(until: start)
                self?.signposts.begin(.intro)
                try await clock.sleep(until: start + .milliseconds(900))
                self?.signposts.end(.intro)
            } catch { self?.signposts.end(.intro) }
        }
    }

    private func updateDiagnosticMoon(_ frame: CGRect, arguments: LaunchArguments) {
        #if DEBUG
            guard let scene = overlayController?.launchScene, let t0 = scene.t0 else { return }
            scene.play(
                LaunchTimeline.opening(size: scene.size, reduceMotion: scene.timeline.reduceMotion)
                    .withWelcomeExit(at: .milliseconds(1600), size: scene.size, moonTarget: frame), at: t0)
            if let time = arguments.freezeAt { scene.freeze(at: time) }
            DispatchQueue.main.async { [weak self, weak scene] in
                guard let self, let moon = scene?.layer(.moon).presentation(), let controller = overlayController else {
                    return
                }
                let values: [String: [Double]] = [
                    "target": [frame.midX, frame.midY, frame.width],
                    "moon": [
                        moon.position.x, moon.position.y, moon.value(forKeyPath: "transform.scale.x") as? Double ?? 0,
                    ],
                ]
                if let data = try? JSONEncoder().encode(values) {
                    controller.view.accessibilityValue = String(decoding: data, as: UTF8.self)
                }
            }
        #endif
    }

    private func finishLaunch() {
        guard let overlay = overlayWindow else { return }
        coordinator?.send(.exitCompleted)
        coordinator?.stop()
        exitSignpostTask?.cancel()
        overlay.isHidden = true
        overlay.rootViewController = nil
        overlayWindow = nil
        overlayController = nil
        if let controller = window?.rootViewController as? LaunchHostingController<RootView> {
            controller.view.accessibilityElementsHidden = false
            controller.launchIsVisible = false
        }
        signposts.event(.overlayRemoved)
        signposts.end(.exit)
        signposts.end(.launch)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        connectionGeneration += 1
        finishLaunch()
        coordinator?.stop()
        coordinator = nil
        exitSignpostTask?.cancel()
        exitSignpostTask = nil
        introSignpostTask?.cancel()
        introSignpostTask = nil
        launchIntro = nil
        window?.isHidden = true
        window = nil
        rootScheduled = false
    }
}

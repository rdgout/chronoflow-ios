import AppCore
import DataAccess
import DesignSystem
import Launch
import SwiftUI
import TripWizard
import UIKit
import UserNotifications

#if DEBUG
    import Sync
#endif

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private(set) var overlayWindow: UIWindow?
    private(set) var overlayController: LaunchOverlayController?
    private(set) var pendingIntent = PendingLaunchIntent()
    private(set) var pendingAuthLink: AuthLink?
    var authLinkHandler: ((AuthLink) -> Void)?
    private(set) var coordinator: LaunchCoordinator?
    var navigator = RootNavigator()
    private(set) var moonAnchorStore = MoonAnchorStore()
    let signposts = LaunchSignposts()
    private var exitSignpostTask: Task<Void, Never>?
    private var introSignpostTask: Task<Void, Never>?
    private var guestRecoveryTask: Task<Void, Never>?
    private var checkedGuestRecovery = false
    private(set) var launchIntro: LaunchIntro?
    private var allowsIntro = false
    var serviceConfigurationFactory: (@Sendable () async throws -> (AppServices, URL?))?
    var nativeSessionFactory: (@MainActor (AppServices, URL) -> NativeSessionController)?
    var readinessFactory: (@MainActor (LaunchArguments, any LaunchClock) -> any LaunchReadiness)?
    private(set) var nativeSession: NativeSessionController?
    private(set) var serviceFailure: (any Error)?
    private var serviceConfiguration: (AppServices, URL?)?
    private var servicesTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var isActive = true
    private var unlockObserver: NSObjectProtocol?
    private var rootScheduled = false
    private var connectionGeneration = 0
    #if DEBUG
        private var recordedSessionReady = false
        private var uiTestAuthorization: String?
        private var uiTestNonce: String?
        private var uiTestResetTask: Task<Void, Never>?
        private var uiTestLaunchArguments: [String]?
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
            let app = UIApplication.shared.delegate as? AppDelegate
        else { return }
        captureAuthActivities(connectionOptions.userActivities)
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
        #if DEBUG
            if !connectionOptions.urlContexts.isEmpty {
                receiveUITestURLs(connectionOptions.urlContexts.map(\.url), delivery: "connection")
            }
        #endif
    }

    func connect(to windowScene: UIWindowScene, firstConnection: Bool, arguments: LaunchArguments = LaunchArguments()) {
        connectionGeneration += 1
        #if DEBUG
            if let test = AuthUITestConfiguration(environment: UITestRuntime.environment), test.fastLaunch {
                uiTestAuthorization = UITestRuntime.environment["CF_AUTH_TEST_ID"]
                uiTestNonce = test.id
                uiTestLaunchArguments =
                    UITestRuntime.environment["CF_UI_TEST_LAUNCH_ARGUMENTS"]
                    .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) }
                    ?? UITestRuntime.arguments
            }
        #endif
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
            #if DEBUG
                UITestTimeline.record("overlay-committed")
            #endif
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
        #if DEBUG
            if AuthUITestConfiguration(environment: UITestRuntime.environment)?.fastLaunch == true {
                allowsIntro = false
                UIView.setAnimationsEnabled(false)
            }
        #endif
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
        if !firstConnection,
            let native = nativeSession
                ?? (nativeSessionFactory == nil ? (UIApplication.shared.delegate as? AppDelegate)?.nativeSession : nil)
        {
            nativeSession = native
            native.observe()
            setActive(isActive)
        }
    }

    #if DEBUG
        private var usesFastUITestLaunch: Bool {
            AuthUITestConfiguration(environment: UITestRuntime.environment)?.fastLaunch == true
        }
    #endif

    private func configurationLoader() -> @Sendable () async throws -> (AppServices, URL?) {
        if let serviceConfigurationFactory { return serviceConfigurationFactory }
        #if DEBUG
            let environment = UITestRuntime.environment
            let arguments = UITestRuntime.arguments
            return { try await AppServices.uiTestLaunchConfiguration(environment: environment, arguments: arguments) }
        #else
            return { try await AppServices.launchConfiguration() }
        #endif
    }

    #if DEBUG
        func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
            receiveUITestURLs(contexts.map(\.url), delivery: "openURLContexts")
        }

        func receiveUITestURLs(_ urls: [URL], delivery: String) {
            UITestTimeline.record(
                "url-received", details: "delivery=\(delivery) count=\(urls.count)", allowUngated: true)
            for url in urls {
                do {
                    let command = try UITestSeedCommand(validating: url, authorizedID: uiTestAuthorization)
                    UITestTimeline.record(
                        "reseed-authorized", environment: command.environment,
                        details: "nonce=\(command.nonce) delivery=\(delivery)")
                    enqueueUITestReseed(command)
                } catch {
                    UITestTimeline.record(
                        "url-rejected", details: "delivery=\(delivery) reason=\(error)", allowUngated: true)
                }
            }
        }

        func enqueueUITestReseed(_ command: UITestSeedCommand) {
            let previous = uiTestResetTask
            uiTestResetTask = Task { [weak self] in
                await previous?.value
                await self?.reseedUITest(command)
            }
        }

        private func reseedUITest(_ command: UITestSeedCommand) async {
            let changed = command.changedLaunchSettings(
                arguments: uiTestLaunchArguments ?? UITestRuntime.arguments, environment: command.environment)
            guard usesFastUITestLaunch, changed.isEmpty else {
                UITestTimeline.record(
                    "reset-rejected", environment: command.environment,
                    details:
                        "nonce=\(command.nonce) reason=launch-settings-or-profile changed=\(changed.joined(separator: ","))"
                )
                return
            }
            guard let app = UIApplication.shared.delegate as? AppDelegate, let windowScene = window?.windowScene else {
                UITestTimeline.record(
                    "reset-rejected", environment: command.environment,
                    details: "nonce=\(command.nonce) reason=no-connected-window")
                return
            }
            UITestTimeline.record("reset-begin", environment: command.environment, details: "nonce=\(command.nonce)")
            do {
                let endedEditing = window?.endEditing(true) ?? true
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                UITestTimeline.record(
                    "reset-editing-ended", environment: command.environment,
                    details: "nonce=\(command.nonce) ended=\(endedEditing)")
                connectionGeneration += 1
                let loading = servicesTask
                servicesTask?.cancel()
                await loading?.value
                servicesTask = nil
                activityTask?.cancel()
                await activityTask?.value
                activityTask = nil
                coordinator?.stop()
                coordinator = nil
                if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
                unlockObserver = nil
                window?.endEditing(true)
                window?.rootViewController?.dismiss(animated: false)
                window?.rootViewController = nil
                window?.isHidden = true
                window = nil
                rootScheduled = false
                pendingAuthLink = nil
                pendingIntent = PendingLaunchIntent()
                authLinkHandler = nil
                try await UITestSessionFixture.tearDown(native: nativeSession, auth: app.authServices)
                if let (services, root) = serviceConfiguration, let root {
                    try await MockSessionSeed.reset(
                        applicationSupport: root, credentials: services.sessionCredentials())
                }
                if let oldID = UITestRuntime.environment["CF_AUTH_TEST_ID"], let uuid = UUID(uuidString: oldID) {
                    UserDefaults().removePersistentDomain(forName: "ChronoFlow.Settings.UITest.\(uuid.uuidString)")
                }
                nativeSession = nil
                app.authServices = nil
                app.nativeSession = nil
                app.authWindow = nil
                app.uiTestEnvironment = command.environment
                app.uiTestArguments = [ProcessInfo.processInfo.arguments[0]] + command.arguments
                app.navigator = RootNavigator()
                navigator = app.navigator
                guestRecoveryTask?.cancel()
                checkedGuestRecovery = false
                serviceFailure = nil
                serviceConfiguration = try await Task.detached {
                    try await AppServices.uiTestLaunchConfiguration(
                        environment: command.environment, arguments: command.arguments, reset: true)
                }.value
                UITestTimeline.record("configuration-ready", details: "nonce=\(command.nonce)")
                if let (services, root) = serviceConfiguration, let root {
                    let native = configureSession(services: services, root: root)
                    native.observe()
                    await native.setActive(isActive)
                }
                uiTestNonce = command.nonce
                moonAnchorStore = MoonAnchorStore()
                await UITestSessionFixture.route(native: nativeSession, navigator: navigator) { epoch in
                    await (UIApplication.shared.delegate as? AppDelegate)?.verificationRequired(epoch: epoch)
                }
                UITestTimeline.record("session-ready")
                mountRoot(on: windowScene)
            } catch {
                serviceFailure = error
                let failed = UIWindow(windowScene: windowScene)
                failed.rootViewController = UIViewController()
                failed.accessibilityIdentifier = "uitest.failed.\(command.nonce)"
                window = failed
                failed.makeKeyAndVisible()
                UITestTimeline.record(
                    "reset-failed", environment: command.environment, details: "nonce=\(command.nonce) error=\(error)")
            }
        }
    #endif

    private func startReadiness(on windowScene: UIWindowScene, arguments: LaunchArguments) {
        #if DEBUG
            let injectedReadiness = arguments.usesInjectedReadiness && !usesFastUITestLaunch
        #else
            let injectedReadiness = arguments.usesInjectedReadiness
        #endif
        let clock = MediaLaunchClock(t0: overlayController?.launchScene.t0 ?? CACurrentMediaTime())
        let safe = overlayController?.view.safeAreaInsets ?? windowScene.keyWindow?.safeAreaInsets ?? .zero
        let size = overlayController?.launchScene.size ?? windowScene.coordinateSpace.bounds.size
        let fallback = MoonTarget.fallback(
            size: size, safeAreaInsets: .init(top: safe.top, left: safe.left, bottom: safe.bottom, right: safe.right),
            rowHeight: LaunchArguments.fallbackRowHeight(compatibleWith: windowScene.traitCollection))
        if let source = readinessFactory?(arguments, clock) {
            runReadiness(source, on: windowScene, clock: clock, fallback: fallback)
        } else if injectedReadiness {
            runReadiness(
                StubReadiness(configuration: arguments.readiness, store: KeychainSessionStore(), clock: clock),
                on: windowScene, clock: clock, fallback: fallback)
        } else {
            let generation = connectionGeneration
            servicesTask = Task { [weak self, weak windowScene] in
                do {
                    let load = self?.configurationLoader()
                    let configuration = try await Task.detached {
                        if let load { return try await load() }
                        return try await AppServices.launchConfiguration()
                    }.value
                    guard let self, let windowScene, !Task.isCancelled, connectionGeneration == generation else {
                        return
                    }
                    serviceConfiguration = configuration
                    #if DEBUG
                        UITestTimeline.record("configuration-ready")
                    #endif
                    let source: any LaunchReadiness
                    if configuration.0.signedOutReadiness {
                        source = SignedOutReadiness()
                    } else {
                        guard let root = configuration.1 else {
                            throw AppServices.Failure.applicationSupportUnavailable
                        }
                        let native = configureSession(services: configuration.0, root: root)
                        native.observe()
                        await native.setActive(isActive)
                        guard !Task.isCancelled, connectionGeneration == generation else { return }
                        source = native.readiness
                        unlockObserver = NotificationCenter.default.addObserver(
                            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil,
                            queue: .main
                        ) { [weak native] _ in
                            Task { @MainActor in await native?.readiness.retry() }
                        }
                    }
                    #if DEBUG
                        if configuration.0.fastUITestLaunch {
                            await UITestSessionFixture.route(native: nativeSession, navigator: navigator) { epoch in
                                await (UIApplication.shared.delegate as? AppDelegate)?.verificationRequired(
                                    epoch: epoch)
                            }
                            UITestTimeline.record("session-ready")
                            finishLaunch()
                            mountRoot(on: windowScene)
                            return
                        }
                    #endif
                    runReadiness(source, on: windowScene, clock: clock, fallback: fallback)
                } catch {
                    guard let self, let windowScene, !Task.isCancelled, connectionGeneration == generation else {
                        return
                    }
                    serviceFailure = error
                    runReadiness(UnavailableReadiness(), on: windowScene, clock: clock, fallback: fallback)
                }
            }
        }
    }

    private func configureSession(services: AppServices, root: URL) -> NativeSessionController {
        if let nativeSession { return nativeSession }
        let app = UIApplication.shared.delegate as? AppDelegate
        let native: NativeSessionController
        if let factory = nativeSessionFactory {
            native = factory(services, root)
        } else if let existing = app?.nativeSession {
            native = existing
        } else {
            native = NativeSessionController(
                applicationSupport: root, namespace: services.namespace, credentials: services.sessionCredentials(),
                reminderCenter: services.reminderCenter(),
                source: { session in services.makeDataSource(applicationSupport: root, session: session) },
                verification: { [weak app] epoch in await app?.verificationRequired(epoch: epoch) },
                signedOut: { [navigator] in navigator.navigate(to: .signIn) })
            app?.nativeSession = native
        }
        nativeSession = native
        UNUserNotificationCenter.current().delegate = app
        return native
    }

    private func runReadiness(
        _ source: any LaunchReadiness, on windowScene: UIWindowScene,
        clock: any LaunchClock, fallback: CGRect
    ) {
        var navigationRevision = navigator.revision
        let coordinator = LaunchCoordinator(
            readiness: source, clock: clock,
            reduceMotion: overlayController?.launchScene.timeline.reduceMotion ?? true,
            state: .init(fallbackTarget: fallback, pendingIntent: pendingIntent)
        ) { [weak self, weak windowScene] state, effects in
            guard let self, let windowScene else { return }
            if state.session != nil {
                signposts.end(.session)
                #if DEBUG
                    if !recordedSessionReady {
                        recordedSessionReady = true
                        UITestTimeline.record("session-ready")
                    }
                #endif
            }
            if state.isReady { signposts.end(.ready) }
            if let route = state.route {
                if route == .welcome, allowsIntro, launchIntro == nil, let start = state.exitStart {
                    launchIntro = LaunchIntro(start: start + .milliseconds(700), clock: clock)
                    scheduleIntroSignpost(clock: clock, start: start + .milliseconds(700))
                }
                if navigator.revision == navigationRevision {
                    navigator.navigate(to: route)
                    navigationRevision = navigator.revision
                }
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
                #if DEBUG
                    if usesFastUITestLaunch { window.layer.speed = 20 }
                #endif
                let app = UIApplication.shared.delegate as? AppDelegate
                if serviceConfiguration == nil {
                    let load = configurationLoader()
                    do {
                        serviceConfiguration = try await Task.detached {
                            return try await load()
                        }.value
                    } catch { serviceFailure = error }
                }
                guard connectionGeneration == generation else { return }
                if let (services, root) = serviceConfiguration, !services.signedOutReadiness, let root {
                    let native = configureSession(services: services, root: root)
                    if nativeSessionFactory == nil, app?.authServices == nil {
                        app?.authServices = AuthSessionServices(
                            services: services, applicationSupport: root, nativeSession: native,
                            navigator: navigator, anchor: { [weak app] in app?.authWindow },
                            verification: { [weak app] epoch in
                                await app?.verificationRequired(epoch: epoch)
                            })
                    }
                }
                #if DEBUG
                    if let test = AuthUITestConfiguration(environment: UITestRuntime.environment),
                        let auth = app?.authServices
                    {
                        if test.auditScreen == "two-factor" {
                            navigator.navigate(to: .signIn)
                            await test.prepareChallenge(auth.model)
                        } else {
                            do { try await auth.prepareUITestRoute(test, navigator: navigator) } catch {
                                serviceFailure = error
                                UITestTimeline.record("seed-route-failed")
                            }
                        }
                    }
                    if app?.authServices?.authUITestEnabled == true,
                        let value = UITestRuntime.environment["CF_AUTH_TEST_LINK"],
                        let url = URL(string: value)
                    {
                        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                        activity.webpageURL = url
                        captureAuthActivities([activity])
                    }
                #endif
                if navigator.route == .verify { await app?.authServices?.prepareVerification() }
                consumePendingAuthLink()
                let controller = LaunchHostingController(
                    rootView: RootView(
                        navigator: navigator, authModel: app?.authServices?.model, authServices: app?.authServices,
                        moonAnchorStore: moonAnchorStore,
                        launchIntro: launchIntro,
                        forcesReduceMotion: overlayController?.launchScene.timeline.reduceMotion ?? false),
                    signposts: signposts)
                #if DEBUG
                    controller.uiTestReadinessID = uiTestNonce
                    controller.uiTestIsReseed =
                        uiTestNonce != AuthUITestConfiguration(environment: UITestRuntime.environment)?.id
                #endif
                controller.launchIsVisible = overlayWindow != nil
                window.rootViewController = controller
                ContentSizeCap.apply(to: controller, in: window)
                controller.view.accessibilityElementsHidden = overlayWindow != nil
                self.window = window
                app?.authWindow = window
                window.makeKeyAndVisible()
                consumePendingReminderIntent()
                scheduleGuestRecovery()
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

    private func scheduleGuestRecovery() {
        guard !checkedGuestRecovery, window != nil, overlayWindow == nil, navigator.route == .welcome,
            let nativeSession, launchIntro?.frozenTime == nil
        else { return }
        checkedGuestRecovery = true
        let revision = navigator.revision
        let generation = connectionGeneration
        let intro = launchIntro
        guestRecoveryTask = Task { [weak self] in
            do {
                if let intro { try await intro.clock.sleep(until: intro.start + .milliseconds(900)) }
                guard let self, !Task.isCancelled, connectionGeneration == generation,
                    navigator.revision == revision, navigator.route == .welcome,
                    await nativeSession.controller.presence == .signedOut
                else { return }
                let decision = try await nativeSession.guestWizardStore.recoveryDecision(
                    handoffFinished: true, introFinished: true)
                guard !Task.isCancelled, connectionGeneration == generation, navigator.revision == revision else {
                    return
                }
                switch decision {
                case .wizard: navigator.navigate(to: .guestWizard)
                case .signIn: navigator.navigate(to: .signIn)
                case .none, .wait, .expire: break
                }
            } catch { return }
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
        nativeSession?.observeGates(navigator: navigator) { epoch in
            await (UIApplication.shared.delegate as? AppDelegate)?.verificationRequired(epoch: epoch)
        }
        consumePendingReminderIntent()
        scheduleGuestRecovery()
        #if DEBUG
            if let window, window.rootViewController?.viewIfLoaded != nil {
                window.layoutIfNeeded()
                (window.rootViewController as? LaunchHostingController<RootView>)?.recordVisibleScreen()
            }
        #endif
        signposts.event(.overlayRemoved)
        signposts.end(.exit)
        signposts.end(.launch)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func receiveReminderIntent(_ intent: PendingLaunchIntent) {
        pendingIntent = intent
        consumePendingReminderIntent()
    }

    private func consumePendingReminderIntent() {
        guard overlayWindow == nil, let nativeSession else { return }
        nativeSession.reminderTaps.receive(pendingIntent)
        pendingIntent = PendingLaunchIntent()
    }

    func captureAuthActivities(_ activities: Set<NSUserActivity>) {
        for activity in activities {
            if activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
                let link = AuthLink(url: url)
            {
                pendingAuthLink = link
                break
            }
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        captureAuthActivities([userActivity])
        consumePendingAuthLink()
    }

    func consumePendingAuthLink() {
        if let link = pendingAuthLink, let authLinkHandler {
            pendingAuthLink = nil
            authLinkHandler(link)
            return
        }
        guard let link = pendingAuthLink,
            let auth = (UIApplication.shared.delegate as? AppDelegate)?.authServices
        else { return }
        pendingAuthLink = nil
        switch link {
        case .verify(let input):
            Task { await auth.receiveVerificationLink(input) }
        case .reset(let input):
            Task { await auth.resetLinks.receive(input) }
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) { setActive(true) }

    func sceneDidEnterBackground(_ scene: UIScene) { setActive(false) }

    private func setActive(_ active: Bool) {
        isActive = active
        let previous = activityTask
        activityTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await nativeSession?.setActive(active)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        connectionGeneration += 1
        setActive(false)
        servicesTask?.cancel()
        servicesTask = nil
        if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
        unlockObserver = nil
        finishLaunch()
        coordinator?.stop()
        coordinator = nil
        exitSignpostTask?.cancel()
        exitSignpostTask = nil
        introSignpostTask?.cancel()
        introSignpostTask = nil
        guestRecoveryTask?.cancel()
        guestRecoveryTask = nil
        launchIntro = nil
        window?.isHidden = true
        window = nil
        rootScheduled = false
    }
}

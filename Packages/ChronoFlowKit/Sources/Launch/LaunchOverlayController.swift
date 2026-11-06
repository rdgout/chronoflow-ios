#if canImport(UIKit)
    import AppCore
    import UIKit

    public final class LaunchOverlayController: UIViewController {
        public let launchScene: LaunchScene
        public private(set) var statusAnnouncementCount = 0
        private var fontsReady = false
        private var needsStatusText = false
        private var generation = 0
        private let accessibilityPost: @MainActor (UIAccessibility.Notification, Any?) -> Void

        public init(
            scene: LaunchScene,
            accessibilityPost: @escaping @MainActor (UIAccessibility.Notification, Any?) -> Void = {
                UIAccessibility.post(notification: $0, argument: $1)
            }
        ) {
            launchScene = scene
            self.accessibilityPost = accessibilityPost
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { return nil }

        public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

        public func prepareAccessibilityLabel() {
            view.accessibilityLabel = String(localized: "ChronoFlow is opening", bundle: .module)
        }

        public func fontsDidRegister() {
            fontsReady = true
            if needsStatusText { launchScene.prepareStatus() }
        }

        public func update(
            state: LaunchState, effects: [LaunchEffect], onExit: @escaping @MainActor @Sendable () -> Void
        ) {
            if state.showsStatus && statusAnnouncementCount == 0 {
                let status = String(localized: "Getting your plan ready", bundle: .module)
                view.accessibilityValue = status
                statusAnnouncementCount = 1
                let announcement = NSAttributedString(
                    string: status, attributes: [.accessibilitySpeechQueueAnnouncement: true])
                accessibilityPost(.announcement, announcement)
            }
            guard
                effects.contains(where: {
                    switch $0 {
                    case .commitExit, .commitStatus, .cancelStatus: true
                    case .forceReady: false
                    }
                }), let t0 = launchScene.t0
            else { return }
            var timeline = LaunchTimeline.opening(
                size: launchScene.size, reduceMotion: launchScene.timeline.reduceMotion)
            needsStatusText = state.statusStart != nil
            if let start = state.statusStart {
                if fontsReady { launchScene.prepareStatus() }
                timeline = timeline.withStatus(at: start)
            }
            if state.didCommitExit, let start = state.exitStart, let ending = state.ending {
                timeline =
                    ending == .app
                    ? timeline.withReadyExit(at: start)
                    : timeline.withWelcomeExit(
                        at: start, size: timeline.size, moonTarget: state.moonTarget ?? state.fallbackTarget)
            }
            generation += 1
            let currentGeneration = generation
            launchScene.play(timeline, at: t0)
            if state.didCommitExit, let opacity = launchScene.container.animation(forKey: "opacity") {
                // Isolate completion from the status dots' infinitely repeating transaction.
                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == currentGeneration else { return }
                        onExit()
                    }
                }
                launchScene.container.add(opacity, forKey: "opacity")
                CATransaction.commit()
            }
        }

        public override func loadView() {
            let frame = LaunchFrameView(
                frame: CGRect(origin: .zero, size: launchScene.size), traits: launchScene.traits)
            frame.install(launchScene)
            frame.isAccessibilityElement = true
            frame.accessibilityTraits = .image
            frame.accessibilityIdentifier = "launch.opening"
            frame.accessibilityViewIsModal = true
            view = frame
        }
    }
#endif

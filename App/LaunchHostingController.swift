import AppCore
import SwiftUI
import UIKit

final class LaunchHostingController<Content: View>: UIHostingController<Content> {
    var launchIsVisible = true {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }
    private let signposts: LaunchSignposts
    private var recordedLayout = false
    #if DEBUG
        private var recordedVisibleScreen = false
        func recordVisibleScreen() {
            guard !recordedVisibleScreen, !launchIsVisible, view.window != nil else { return }
            recordedVisibleScreen = true
            UITestTimeline.record("seeded-screen-visible")
        }
    #endif

    init(rootView: Content, signposts: LaunchSignposts) {
        self.signposts = signposts
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override var preferredStatusBarStyle: UIStatusBarStyle { launchIsVisible ? .lightContent : .default }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if DEBUG
            recordVisibleScreen()
            if let window = view.window {
                let frame = window.safeAreaLayoutGuide.layoutFrame
                if let data = try? JSONEncoder().encode([frame.minX, frame.minY, frame.width, frame.height]) {
                    window.accessibilityValue = String(decoding: data, as: UTF8.self)
                }
            }
        #endif
        if !recordedLayout {
            recordedLayout = true
            signposts.event(.rootFirstLayout)
        }
    }
}

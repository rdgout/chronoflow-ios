import AppCore
import SwiftUI
import UIKit

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

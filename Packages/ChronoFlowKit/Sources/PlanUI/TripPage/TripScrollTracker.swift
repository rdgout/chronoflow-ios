import PlanCore
import SwiftUI

final class TripScrollTracker {
    var frames: [String: CGRect] = [:]
    private(set) var opacity: Double = 0
    #if os(iOS)
        weak var chrome: UIView?
    #endif

    func updateChrome(dayID: String, reduceMotion: Bool) {
        let remaining = frames["header." + dayID]?.maxY ?? .infinity
        opacity =
            reduceMotion ? (remaining <= 0 ? 1 : 0) : min(1, max(0, 1 - remaining / PlanMetrics.compactFadeDistance))
        #if os(iOS)
            chrome?.alpha = opacity
            chrome?.accessibilityElementsHidden = opacity < 1
        #endif
    }
}

#if os(iOS)
    import UIKit

    struct CompactHeaderHost<Content: View>: UIViewControllerRepresentable {
        let content: Content
        let tracker: TripScrollTracker

        func makeUIViewController(context: Context) -> UIHostingController<Content> {
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            tracker.chrome = host.view
            host.view.alpha = tracker.opacity
            host.view.accessibilityElementsHidden = tracker.opacity < 1
            return host
        }

        func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
            host.rootView = content
            tracker.chrome = host.view
            host.view.alpha = tracker.opacity
            host.view.accessibilityElementsHidden = tracker.opacity < 1
        }
    }
#endif

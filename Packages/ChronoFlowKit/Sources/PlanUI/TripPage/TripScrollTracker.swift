import PlanCore
import SwiftUI

final class TripScrollTracker {
    var frames: [String: CGRect] = [:]
    private var anchor: TripPageAnchor?
    private var viewport: CGSize?
    private var layout: TripPageLayout?
    private var pendingAnchor: TripPageAnchor?
    var pendingDayID: String? {
        pendingAnchor?.dayID.flatMap { frames[$0] == nil ? $0 : nil }
    }
    private(set) var opacity: Double = 0
    #if os(iOS)
        weak var chrome: UIView?
        weak var scrollView: UIScrollView?
        private var restorationQueued = false
    #endif

    func track(_ anchor: TripPageAnchor) {
        self.anchor = anchor
        if let id = anchor.dayID, let frame = frames[id] {
            self.anchor?.offset = -frame.minY
        }
    }

    func resize(frames: [String: CGRect], viewport: CGSize, layout: TripPageLayout, anchor: TripPageAnchor) -> Bool {
        if self.viewport != nil && (self.viewport != viewport || self.layout != layout) {
            let preserved = pendingAnchor ?? self.anchor ?? anchor
            pendingAnchor = preserved.dayID == nil ? nil : preserved
        }
        self.viewport = viewport
        self.layout = layout
        self.frames = frames
        guard pendingAnchor != nil else { return false }
        #if os(iOS)
            restoreAfterLayout()
        #else
            self.anchor = pendingAnchor
            pendingAnchor = nil
        #endif
        return true
    }

    #if os(iOS)
        func restoreAfterLayout() {
            guard !restorationQueued, pendingAnchor != nil else { return }
            restorationQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                restorationQueued = false
                restorePosition()
            }
        }

        private func restorePosition() {
            guard let pendingAnchor, let id = pendingAnchor.dayID, let frame = frames[id], let scrollView else {
                return
            }
            let lower = -scrollView.adjustedContentInset.top
            let upper = max(
                lower, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            let target = scrollView.contentOffset.y + frame.minY + pendingAnchor.offset
            anchor = pendingAnchor
            self.pendingAnchor = nil
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: min(upper, max(lower, target))), animated: false)
        }
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

    struct TripScrollHost: UIViewRepresentable {
        let tracker: TripScrollTracker

        func makeUIView(context: Context) -> ScrollProbe { ScrollProbe(tracker: tracker) }
        func updateUIView(_ view: ScrollProbe, context: Context) {}

        final class ScrollProbe: UIView {
            let tracker: TripScrollTracker

            init(tracker: TripScrollTracker) {
                self.tracker = tracker
                super.init(frame: .zero)
                isUserInteractionEnabled = false
            }

            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                var ancestor = superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView {
                        tracker.scrollView = scroll
                        tracker.restoreAfterLayout()
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }

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

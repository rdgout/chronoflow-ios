import PlanCore
import SwiftUI

final class TripScrollTracker {
    var frames: [String: CGRect] = [:]
    private var anchor: TripPageAnchor?
    private var viewport: CGSize?
    private var layout: TripPageLayout?
    private var restoration: TripScrollRestoration?
    var pendingDayID: String? {
        restoration?.anchor.dayID.flatMap { frames[$0] == nil ? $0 : nil }
    }
    private(set) var opacity: Double = 0
    #if os(iOS)
        weak var chrome: UIView?
        weak var scrollView: UIScrollView?
        let dayViews = NSMapTable<NSString, UIView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
        private var displayLink: CADisplayLink?
    #endif

    func track(_ anchor: TripPageAnchor) {
        guard restoration == nil else { return }
        self.anchor = anchor
        if let id = anchor.dayID, let frame = frames[id] {
            self.anchor?.offset = -frame.minY
        }
    }

    func beginResize() {
        guard restoration == nil, let anchor, anchor.dayID != nil else { return }
        restoration = TripScrollRestoration(anchor: anchor)
        #if os(iOS)
            restoreAfterLayout()
        #endif
    }

    func cancelRestoration() {
        #if os(iOS)
            displayLink?.invalidate()
            displayLink = nil
        #endif
        restoration = nil
    }

    func resize(frames: [String: CGRect], viewport: CGSize, layout: TripPageLayout, anchor: TripPageAnchor) -> Bool {
        if self.viewport != nil && (self.viewport != viewport || self.layout != layout) {
            if self.anchor == nil { self.anchor = anchor }
            beginResize()
        }
        self.viewport = viewport
        self.layout = layout
        self.frames = frames
        guard restoration != nil else { return false }
        #if os(iOS)
            restoreAfterLayout()
        #else
            self.anchor = restoration?.anchor
            restoration = nil
        #endif
        return true
    }

    #if os(iOS)
        func restoreAfterLayout() {
            guard displayLink == nil, restoration != nil else { return }
            let observer = RestorationObserver(tracker: self)
            let link = CADisplayLink(target: observer, selector: #selector(RestorationObserver.tick))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        fileprivate func restorePosition() {
            guard let scrollView, scrollView.window != nil else {
                cancelRestoration()
                return
            }
            guard !scrollView.isTracking, !scrollView.isDecelerating else {
                cancelRestoration()
                return
            }
            guard let window = scrollView.window,
                layout == TripPageLayout.resolve(width: window.bounds.width, height: window.bounds.height),
                viewport == scrollView.bounds.size,
                let id = restoration?.anchor.dayID, let day = dayViews.object(forKey: id as NSString),
                day.window === window
            else {
                return
            }
            let lower = -scrollView.adjustedContentInset.top
            let upper = max(
                lower, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            )
            // Read both together; cached preference frames can precede UIKit's lazy-stack adjustments.
            let sample = TripScrollRestoration.Sample(
                dayOrigin: day.convert(.zero, to: scrollView).y, contentOffset: scrollView.contentOffset.y,
                contentSize: scrollView.contentSize, viewport: scrollView.bounds.size,
                lower: lower, upper: upper, scale: window.screen.scale)
            guard let target = restoration?.target(for: sample) else { return }
            if restoration?.observe(sample) == true {
                anchor = restoration?.anchor
                cancelRestoration()
                return
            }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: target), animated: false)
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

    private final class RestorationObserver: NSObject {
        private weak var tracker: TripScrollTracker?

        init(tracker: TripScrollTracker) { self.tracker = tracker }

        @objc func tick(_ link: CADisplayLink) {
            guard let tracker else {
                link.invalidate()
                return
            }
            tracker.restorePosition()
        }
    }

    struct TripScrollHost: UIViewRepresentable {
        let tracker: TripScrollTracker
        var dayID: String? = nil

        func makeUIView(context: Context) -> ScrollProbe { ScrollProbe(tracker: tracker, dayID: dayID) }
        func updateUIView(_ view: ScrollProbe, context: Context) {}

        final class ScrollProbe: UIView {
            let tracker: TripScrollTracker
            let dayID: String?

            init(tracker: TripScrollTracker, dayID: String?) {
                self.tracker = tracker
                self.dayID = dayID
                super.init(frame: .zero)
                isUserInteractionEnabled = false
            }

            required init?(coder: NSCoder) { nil }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if let dayID {
                    if window != nil { tracker.dayViews.setObject(self, forKey: dayID as NSString) }
                    return
                }
                guard window != nil else {
                    tracker.cancelRestoration()
                    return
                }
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
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            tracker.chrome = host.view
            host.view.alpha = tracker.opacity
            host.view.accessibilityElementsHidden = tracker.opacity < 1
            return host
        }

        func sizeThatFits(
            _ proposal: ProposedViewSize, uiViewController: UIHostingController<Content>, context: Context
        ) -> CGSize? {
            uiViewController.sizeThatFits(
                in: CGSize(width: proposal.width ?? 0, height: .greatestFiniteMagnitude))
        }

        func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
            host.rootView = content
            tracker.chrome = host.view
            host.view.alpha = tracker.opacity
            host.view.accessibilityElementsHidden = tracker.opacity < 1
        }
    }
#endif

nonisolated struct TripScrollRestoration {
    let anchor: TripPageAnchor
    private var previous: Sample?

    struct Sample: Equatable {
        let dayOrigin: Double
        let contentOffset: Double
        let contentSize: CGSize
        let viewport: CGSize
        let lower: Double
        let upper: Double
        let scale: Double
    }

    init(anchor: TripPageAnchor) { self.anchor = anchor }

    func target(for sample: Sample) -> Double {
        min(sample.upper, max(sample.lower, sample.dayOrigin + anchor.offset))
    }

    mutating func observe(_ sample: Sample) -> Bool {
        defer { previous = sample }
        return previous == sample && abs(sample.contentOffset - target(for: sample)) < 0.5 / sample.scale
    }
}

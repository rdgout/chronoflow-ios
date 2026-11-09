import CoreGraphics

nonisolated enum AuthScrollGesture {
    struct TextRevealProgress {
        enum Decision: Equatable {
            case measure(CGRect)
            case scroll
            case blocked
        }

        private var previousFrame: CGRect?
        private var previousViewport: CGRect?

        mutating func observe(frame: CGRect, visible: CGRect, preferred: CGRect, canScroll: Bool) -> Decision {
            guard !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return .blocked }
            if preferred.contains(frame) { return .measure(preferred) }
            let stopped = previousFrame == frame && previousViewport == visible
            previousFrame = frame
            previousViewport = visible
            if !canScroll || stopped {
                return visible.contains(frame) ? .measure(visible) : .blocked
            }
            return .scroll
        }
    }

    static func readingViewport(
        _ viewport: CGRect, navigationBar: CGRect?, tabBar: CGRect?, clearance: CGFloat
    ) -> CGRect {
        let top = max(viewport.minY, navigationBar?.maxY ?? viewport.minY) + clearance
        let bottom = min(viewport.maxY, tabBar?.minY ?? viewport.maxY) - clearance
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
    }

    static func viewport(
        window: CGRect, safeArea: CGRect, scroll: CGRect, keyboard: CGRect?, includingNavigationBar: Bool = false
    ) -> CGRect {
        var viewport = safeArea.intersection(window).intersection(scroll)
        if includingNavigationBar, !viewport.isEmpty, !viewport.isNull {
            viewport = CGRect(
                x: viewport.minX, y: window.minY, width: viewport.width, height: viewport.maxY - window.minY)
        }
        if let keyboard, SoftwareKeyboardVisibility.isVisible(keyboard, in: window) {
            viewport.size.height = max(0, min(viewport.maxY, keyboard.minY) - viewport.minY)
        }
        return viewport
    }

    static func fullyVisible(_ frame: CGRect, in viewport: CGRect) -> Bool {
        guard !frame.isEmpty, !frame.isInfinite, !frame.isNull,
            !viewport.isEmpty, !viewport.isInfinite, !viewport.isNull
        else { return false }
        // AX audit coordinates round-trip through Float.
        return viewport.insetBy(dx: -0.01, dy: -0.01).contains(frame)
    }

    static func reveal(_ frame: CGRect, in viewport: CGRect) -> (start: CGPoint, end: CGPoint)? {
        guard !viewport.isEmpty, !viewport.isInfinite, !viewport.isNull else { return nil }
        let upward = frame.maxY > viewport.maxY
        let distance = upward ? frame.maxY - viewport.maxY : viewport.minY - frame.minY
        guard distance > 0 else { return nil }
        let margin = viewport.height / 10
        let travel = min(viewport.height - 2 * margin, max(distance + margin, viewport.height / 4))
        let y = upward ? viewport.maxY - margin : viewport.minY + margin
        return (
            CGPoint(x: viewport.midX, y: y),
            CGPoint(x: viewport.midX, y: upward ? y - travel : y + travel)
        )
    }
}

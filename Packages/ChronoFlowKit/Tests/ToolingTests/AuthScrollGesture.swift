import CoreGraphics

nonisolated enum AuthScrollGesture {
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

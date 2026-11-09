import CoreGraphics

nonisolated enum AuthScrollGesture {
    static func viewport(window: CGRect, safeArea: CGRect, scroll: CGRect, keyboard: CGRect?) -> CGRect {
        var viewport = safeArea.intersection(window).intersection(scroll)
        if let keyboard, SoftwareKeyboardVisibility.isVisible(keyboard, in: window) {
            viewport.size.height = max(0, min(viewport.maxY, keyboard.minY) - viewport.minY)
        }
        return viewport
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

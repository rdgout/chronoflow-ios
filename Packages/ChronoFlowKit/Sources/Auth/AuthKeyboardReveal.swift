#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    struct AuthKeyboardReveal: UIViewRepresentable {
        var field: CGRect?
        var submit: CGRect?
        var onOverflow: (Bool) -> Void = { _ in }

        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            view.isUserInteractionEnabled = false
            context.coordinator.view = view
            return view
        }
        func updateUIView(_ uiView: UIView, context: Context) {
            context.coordinator.configuration = self
            context.coordinator.schedule()
        }
        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject {
            weak var view: UIView?
            var configuration: AuthKeyboardReveal?
            private var keyboard: CGRect?
            private var scheduled = false
            override init() {
                super.init()
                NotificationCenter.default.addObserver(
                    self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil)
                NotificationCenter.default.addObserver(
                    self, selector: #selector(keyboardChanged), name: UIResponder.keyboardDidChangeFrameNotification,
                    object: nil)
            }
            @objc private func keyboardChanged(_ notification: Notification) {
                keyboard = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                schedule()
            }
            func schedule() {
                guard !scheduled else { return }
                scheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    scheduled = false
                    reveal()
                }
            }
            private func reveal() {
                guard let configuration, let field = configuration.field, let submit = configuration.submit,
                    let view, let window = view.window
                else { return }
                var parent = view.superview
                while parent != nil && !(parent is UIScrollView) { parent = parent?.superview }
                guard let scroll = parent as? UIScrollView,
                    !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating
                else { return }
                var viewport = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
                if let keyboard {
                    let local = window.convert(keyboard, from: window.screen.coordinateSpace)
                    if local.intersects(viewport) { viewport.size.height = max(0, local.minY - viewport.minY) }
                }
                guard viewport.height > 0 else { return }
                viewport = viewport.insetBy(dx: 0, dy: AuthTokens.fieldGap)
                let result = AuthLayout.reveal(field: field, submit: submit, viewport: viewport)
                configuration.onOverflow(!result.fits)
                let maximum = max(
                    -scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let next = min(maximum, max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + result.offset))
                if abs(next - scroll.contentOffset.y) > 0.5 {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
                }
            }
            deinit { NotificationCenter.default.removeObserver(self) }
        }
    }
#endif

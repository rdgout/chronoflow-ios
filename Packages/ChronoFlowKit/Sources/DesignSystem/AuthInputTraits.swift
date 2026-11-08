#if canImport(UIKit)
    import SwiftUI
    import UIKit

    nonisolated public enum AuthPasswordPolicy {
        public static var rules: String {
            "minlength: 12; required: upper; required: lower; required: digit; required: special;"
        }
        public static var hint: String {
            "Use at least 12 characters, with uppercase and lowercase letters, numbers and symbols. Choose a password that has not appeared in a data leak."
        }
    }

    struct AuthInputTraits: UIViewRepresentable {
        let contentType: UITextContentType?
        func makeUIView(context: Context) -> Probe { Probe() }
        func updateUIView(_ view: Probe, context: Context) {
            view.contentType = contentType
            view.setNeedsLayout()
        }
        final class Probe: UIView {
            var contentType: UITextContentType?
            override func layoutSubviews() {
                super.layoutSubviews()
                apply()
            }
            override func didMoveToWindow() {
                super.didMoveToWindow()
                DispatchQueue.main.async { [weak self] in self?.apply() }
            }
            private func apply() {
                func fields(_ view: UIView) -> [UITextField] {
                    (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(fields)
                }
                var ancestor = superview
                while let view = ancestor {
                    let inputs = fields(view)
                    if inputs.count == 1, let field = inputs.first {
                        field.passwordRules =
                            contentType == .newPassword
                            ? UITextInputPasswordRules(descriptor: AuthPasswordPolicy.rules) : nil
                        return
                    }
                    if inputs.count > 1 { return }
                    ancestor = view.superview
                }
            }
        }
    }
#endif

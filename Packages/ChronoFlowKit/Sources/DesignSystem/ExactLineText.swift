#if canImport(UIKit)
    import SwiftUI
    import UIKit

    struct ExactLineText: UIViewRepresentable {
        let text: String
        let font: UIFont
        let lineHeight: CGFloat
        let tracking: CGFloat
        let color: Color
        var underlined = false

        func makeUIView(context: Context) -> ExactLineTextView { ExactLineTextView() }

        func updateUIView(_ view: ExactLineTextView, context: Context) {
            view.font = font
            view.lineHeight = lineHeight
            view.text = NSAttributedString(
                string: text,
                attributes: [
                    .font: font, .kern: tracking, .foregroundColor: UIColor(color),
                    .underlineStyle: underlined ? NSUnderlineStyle.single.rawValue : 0,
                ])
            view.accessibilityLabel = text
            view.setNeedsLayout()
            view.invalidateIntrinsicContentSize()
        }

        func sizeThatFits(_ proposal: ProposedViewSize, uiView: ExactLineTextView, context: Context) -> CGSize? {
            let width = proposal.width ?? uiView.text.size().width
            return CGSize(width: width, height: uiView.layout(width: width).height)
        }
    }

    final class ExactLineTextView: UIView {
        var text = NSAttributedString(string: "")
        var font = UIFont.preferredFont(forTextStyle: .largeTitle)
        var lineHeight: CGFloat = 0

        init() {
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityTraits = .staticText
        }

        required init?(coder: NSCoder) { nil }

        func layout(width: CGFloat) -> ExactLineTextLayout {
            ExactLineTextLayout(text: text, width: width, lineHeight: lineHeight)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let layout = layout(width: bounds.width)
            while subviews.count > layout.ranges.count { subviews.last?.removeFromSuperview() }
            for index in layout.ranges.indices {
                let label: UILabel
                if index < subviews.count {
                    label = subviews[index] as! UILabel
                } else {
                    label = UILabel()
                    label.isAccessibilityElement = false
                    addSubview(label)
                }
                label.attributedText = layout.line(at: index)
                // Natural-height labels let ink overflow the exact line boxes, like CSS half-leading.
                label.frame = layout.frame(for: index, width: bounds.width, naturalHeight: font.lineHeight)
            }
        }
    }
#endif

import SwiftUI

#if canImport(UIKit)
    import UIKit

    public struct WelcomeText: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        public let text: String
        public let style: Typography.Style
        public let color: ColorToken
        public let underlined: Bool

        public init(_ text: String, style: Typography.Style, color: ColorToken, underlined: Bool = false) {
            self.text = text
            self.style = style
            self.color = color
            self.underlined = underlined
        }

        public var body: some View {
            let font = style.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)))
            let ratio = font.pointSize / style.size
            let lineHeight = style.lineHeight.map { $0 * ratio } ?? font.lineHeight
            if lineHeight < font.lineHeight {
                ExactLineText(
                    text: text, font: font, lineHeight: lineHeight, tracking: style.tracking * ratio,
                    color: color.color,
                    underlined: underlined
                )
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: text)
                    .underline(underlined)
                    .font(.custom(style.face.rawValue, fixedSize: font.pointSize))
                    .foregroundStyle(color.color)
                    .tracking(style.tracking * ratio)
                    .lineSpacing(lineHeight - font.lineHeight)
                    .padding(.vertical, (lineHeight - font.lineHeight) / 2)
                    .fixedSize(horizontal: style == Typography.eyebrow, vertical: true)
            }
        }
    }
#endif

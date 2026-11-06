import SwiftUI

#if canImport(UIKit)
    import UIKit

    public struct WelcomeText: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        public let text: String
        public let style: Typography.Style

        public init(_ text: String, style: Typography.Style) {
            self.text = text
            self.style = style
        }

        public var body: some View {
            let font = style.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)))
            let ratio = font.pointSize / style.size
            let lineHeight = style.lineHeight.map { $0 * ratio } ?? font.lineHeight
            Text(verbatim: text)
                .font(.custom(style.face.rawValue, fixedSize: font.pointSize))
                .tracking(style.tracking * ratio)
                .lineSpacing(lineHeight - font.lineHeight)
                .padding(.vertical, (lineHeight - font.lineHeight) / 2)
                .fixedSize(horizontal: style == Typography.eyebrow, vertical: true)
        }
    }
#endif

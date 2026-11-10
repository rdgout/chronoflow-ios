#if canImport(UIKit)
    import DesignSystem
    import SwiftUI

    struct AuthConsent: View {
        @Environment(\.openURL) private var openURL
        let text: String

        var body: some View {
            Text(attributedText).font(Typography.authMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        guard [AuthPolicy.terms.url, AuthPolicy.privacy.url].contains(url) else { return .discarded }
                        openURL(url)
                        return .handled
                    })
        }

        private var attributedText: AttributedString {
            var result = AttributedString()
            var remaining = text[...]
            while let opening = remaining.firstIndex(of: "<"), let end = remaining[opening...].firstIndex(of: ">") {
                result += AttributedString(String(remaining[..<opening]))
                let tag = String(remaining[remaining.index(after: opening)..<end])
                guard let policy = AuthPolicy(rawValue: tag), let closing = remaining.range(of: "</" + tag + ">") else {
                    break
                }
                var link = AttributedString(String(remaining[remaining.index(after: end)..<closing.lowerBound]))
                link.link = policy.url
                link.foregroundColor = ColorToken.foreground.color
                link.underlineStyle = .single
                result += link
                remaining = remaining[closing.upperBound...]
            }
            result += AttributedString(String(remaining))
            return result
        }
    }
#endif

import SwiftUI

#if canImport(UIKit)
    import UIKit

    public enum AuthControlPart: Hashable { case content, glyph, spinner, label, input, errorGlyph, errorText }

    extension View {
        @ViewBuilder fileprivate func authControlMeasure(
            _ part: AuthControlPart, _ measure: ((AuthControlPart, CGRect) -> Void)?
        ) -> some View {
            if let measure {
                onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    measure(part, $0)
                }
            } else {
                self
            }
        }
    }

    public enum AuthGlyph: String, CaseIterable {
        case back = "AuthBack"
        case eye = "AuthEye"
        case alert = "AuthAlert"
        case info = "AuthInfo"
        case check = "AuthCheck"
        case problem = "AuthProblem"
        case key = "AuthKey"
        public var image: Image { Image(rawValue, bundle: .module) }
    }

    public struct AuthButton: View {
        @Environment(\.isEnabled) private var isEnabled
        public enum Kind { case primary, outline, ghost, footer }
        let title: String
        let kind: Kind
        let busy: Bool
        let glyph: AuthGlyph?
        let minimumHeight: CGFloat
        let measure: ((AuthControlPart, CGRect) -> Void)?
        let action: () -> Void
        public init(
            _ title: String, kind: Kind = .primary, busy: Bool = false, glyph: AuthGlyph? = nil,
            minimumHeight: CGFloat = AuthTokens.touch,
            measure: ((AuthControlPart, CGRect) -> Void)? = nil,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.kind = kind
            self.busy = busy
            self.glyph = glyph
            self.minimumHeight = minimumHeight
            self.measure = measure
            self.action = action
        }
        private var foreground: ColorToken {
            switch kind {
            case .primary: .primaryForeground
            case .footer: .skyCopy
            default: .foreground
            }
        }
        public var body: some View {
            Button(action: action) {
                HStack(spacing: AuthTokens.fieldGap) {
                    if busy {
                        ProgressView().controlSize(.mini).tint(foreground.color)
                            .frame(width: AuthTokens.icon, height: AuthTokens.icon)
                            .authControlMeasure(.spinner, measure).accessibilityHidden(true)
                    }
                    if let glyph {
                        glyph.image.resizable().frame(width: AuthTokens.icon, height: AuthTokens.icon)
                            .foregroundStyle(foreground.color).authControlMeasure(.glyph, measure)
                            .accessibilityHidden(true)
                    }
                    WelcomeText(title, style: Typography.authLabel, color: foreground).multilineTextAlignment(.center)
                        .authControlMeasure(.label, measure)
                }
                .authControlMeasure(.content, measure)
                .padding(.horizontal, AuthTokens.spacer)
                .padding(.vertical, AuthTokens.fieldGap)
                .frame(
                    maxWidth: .infinity,
                    minHeight: kind == .footer ? max(AuthTokens.footerHeight, minimumHeight) : minimumHeight
                )
                .background {
                    switch kind {
                    case .primary: Capsule(style: .circular).fill(ColorToken.primary.color)
                    case .outline: Capsule(style: .circular).fill(ColorToken.background.color)
                    case .footer: Capsule(style: .circular).fill(ColorToken.skyCopyBackground.color)
                    case .ghost: EmptyView()
                    }
                }
                .overlay {
                    if kind == .outline {
                        Capsule(style: .circular).strokeBorder(
                            ColorToken.input.color, lineWidth: AuthTokens.borderWidth)
                    }
                }
                .contentShape(Capsule(style: .circular))
                .opacity(isEnabled && !busy ? 1 : AuthTokens.disabledOpacity)
            }
            .buttonStyle(PressStyle())
            .disabled(busy)
        }
    }

    public struct AuthField: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let title: String
        @Binding var text: String
        let secure: Bool
        let error: String?
        let hint: String?
        let placeholder: String?
        let identifier: String
        let contentType: UITextContentType?
        let keyboard: UIKeyboardType
        let submitLabel: SubmitLabel
        let focus: FocusState<String?>.Binding
        let submit: () -> Void
        let measure: ((AuthControlPart, CGRect) -> Void)?

        public init(
            _ title: String, text: Binding<String>, secure: Bool = false, error: String? = nil, hint: String? = nil,
            placeholder: String? = nil,
            identifier: String, contentType: UITextContentType?, keyboard: UIKeyboardType = .default,
            submitLabel: SubmitLabel = .next, focus: FocusState<String?>.Binding,
            measure: ((AuthControlPart, CGRect) -> Void)? = nil, submit: @escaping () -> Void
        ) {
            self.title = title
            _text = text
            self.secure = secure
            self.error = error
            self.hint = hint
            self.placeholder = placeholder
            self.identifier = identifier
            self.contentType = contentType
            self.keyboard = keyboard
            self.submitLabel = submitLabel
            self.focus = focus
            self.submit = submit
            self.measure = measure
        }
        public var body: some View {
            let cappedSize = ContentSizeCap.clamp(dynamicTypeSize)
            let font = Typography.authBody.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(cappedSize)))
            VStack(alignment: .leading, spacing: AuthTokens.fieldGap) {
                WelcomeText(title, style: Typography.authLabel, color: .cardForeground).accessibilityHidden(true)
                Group {
                    if secure {
                        SecureField(text: $text, prompt: Text(verbatim: "")) { Text(verbatim: title) }
                    } else {
                        TextField(
                            text: $text,
                            prompt: Text(verbatim: placeholder ?? "").foregroundColor(ColorToken.mutedForeground.color)
                        ) { Text(verbatim: title) }
                        .accessibilityValue(Text(verbatim: text))
                    }
                }
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(Text(verbatim: title))
                .accessibilityHint(Text(verbatim: error ?? hint ?? ""))
                // SwiftUI's scalable custom font can re-read the uncapped system preference for native text layout.
                .font(.custom(Typography.authBody.face.rawValue, fixedSize: font.pointSize))
                .foregroundStyle(ColorToken.cardForeground.color)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(contentType == .name ? .words : .never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .submitLabel(submitLabel)
                .onSubmit(submit)
                .focused(focus, equals: identifier)
                .environment(\.dynamicTypeSize, cappedSize)
                .padding(.horizontal, AuthTokens.inset)
                .padding(.vertical, AuthTokens.fieldGap)
                .frame(minHeight: AuthTokens.touch)
                .overlay {
                    RoundedRectangle(cornerRadius: AuthTokens.fieldRadius)
                        .strokeBorder(
                            (error != nil ? ColorToken.destructive : focus.wrappedValue == identifier ? .ring : .input)
                                .color,
                            lineWidth: AuthTokens.borderWidth
                        )
                    if focus.wrappedValue == identifier {
                        RoundedRectangle(cornerRadius: AuthTokens.fieldRadius)
                            .inset(by: -AuthTokens.focusWidth)
                            .strokeBorder(ColorToken.ring.color, lineWidth: AuthTokens.focusWidth)
                    }
                }
                .authControlMeasure(.input, measure)
                .opacity(isEnabled ? 1 : AuthTokens.disabledOpacity)
                .contentShape(RoundedRectangle(cornerRadius: AuthTokens.fieldRadius))
                if let error {
                    HStack(alignment: .center, spacing: AuthTokens.brandGap) {
                        AuthGlyph.alert.image.resizable().frame(width: AuthTokens.icon, height: AuthTokens.icon)
                            .authControlMeasure(.errorGlyph, measure)
                            .accessibilityHidden(true)
                        WelcomeText(error, style: Typography.authHint, color: .destructive)
                            .authControlMeasure(.errorText, measure)
                    }.foregroundStyle(ColorToken.destructive.color).accessibilityHidden(true)
                } else if let hint {
                    WelcomeText(hint, style: Typography.authHint, color: .mutedForeground).accessibilityHidden(true)
                }
            }
        }
    }

    public struct AuthBanner: View {
        let title: String
        let message: String
        public init(title: String, message: String) {
            self.title = title
            self.message = message
        }
        public var body: some View {
            HStack(alignment: .top, spacing: AuthTokens.bannerGap) {
                AuthGlyph.alert.image.resizable().frame(width: AuthTokens.bannerGlyph, height: AuthTokens.bannerGlyph)
                    .foregroundStyle(ColorToken.destructive.color).padding(.top, AuthTokens.bannerIconTop)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    WelcomeText(title, style: Typography.authStrong, color: .cardForeground)
                    if !message.isEmpty { WelcomeText(message, style: Typography.authHint, color: .cardForeground) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, AuthTokens.bannerVertical).padding(.horizontal, AuthTokens.bannerHorizontal)
            .background(
                ColorToken.authErrorBackground.color, in: RoundedRectangle(cornerRadius: AuthTokens.bannerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AuthTokens.bannerRadius).strokeBorder(
                    ColorToken.authErrorBorder.color, lineWidth: AuthTokens.borderWidth)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("auth.banner")
        }
    }

    public struct AuthNotice: View {
        @Environment(\.dynamicTypeSize) private var typeSize
        let title: String
        let message: String
        public init(title: String, message: String) {
            self.title = title
            self.message = message
        }
        private var text: AttributedString {
            var text = AttributedString(title + " " + message)
            text.font = Typography.authHint.font
            if let range = text.range(of: title) { text[range].font = Typography.authStrong.font }
            return text
        }
        public var body: some View {
            let style = Typography.authHint
            let font = style.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
            let leading = max(0, (style.lineHeight ?? style.size) * font.pointSize / style.size - font.lineHeight)
            HStack(alignment: .top, spacing: AuthTokens.inset) {
                AuthGlyph.info.image.resizable().frame(width: AuthTokens.icon, height: AuthTokens.icon)
                    .foregroundStyle(ColorToken.mutedForeground.color).padding(.top, AuthTokens.noticeIconTop)
                    .accessibilityHidden(true)
                Text(text).foregroundStyle(ColorToken.cardForeground.color)
                    .lineSpacing(leading).padding(.vertical, leading / 2)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(AuthTokens.inset)
                .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: AuthTokens.noticeRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AuthTokens.noticeRadius).strokeBorder(
                        ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
                .accessibilityElement(children: .combine)
        }
    }
#endif

#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct SignInView: View {
        @Environment(\.locale) private var locale
        @AccessibilityFocusState private var bannerFocused: Bool
        @FocusState private var focus: String?
        @State private var request: Task<Void, Never>?
        @State private var frames: [AuthElement: CGRect] = [:]
        let model: SignInModel
        let back: () -> Void
        let guest: () -> Void
        let measure: (AuthElement, CGRect) -> Void

        public init(
            model: SignInModel, back: @escaping () -> Void, guest: @escaping () -> Void,
            measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }
        ) {
            self.model = model
            self.back = back
            self.guest = guest
            self.measure = measure
        }
        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }
        public var body: some View {
            AuthScreen(
                scrollIdentifier: "sign-in.scroll", title: copy("Welcome back"),
                description: copy("Sign in to see your trips and plans."), back: back,
                measure: report
            ) {
                if let banner = model.form.banner {
                    AuthBanner(title: copy(banner.title), message: copy(banner.body))
                        .id(AuthFeedbackTarget.banner).accessibilityFocused($bannerFocused)
                }
                AuthButton(copy("Sign in with a passkey"), busy: model.form.pending == .passkey, glyph: .key) {
                    submit(.passkey)
                }
                .accessibilityIdentifier("sign-in.passkey").authMeasure(.passkey, report)
                HStack(spacing: AuthTokens.inset) {
                    Rectangle().fill(ColorToken.border.color).frame(height: AuthTokens.borderWidth)
                    WelcomeText(copy("or with email"), style: Typography.authMeta, color: .mutedForeground)
                    Rectangle().fill(ColorToken.border.color).frame(height: AuthTokens.borderWidth)
                }.accessibilityHidden(true)
                AuthField(
                    copy("Email"), text: Binding(get: { model.email }, set: model.editEmail),
                    error: model.form.fields["email"].flatMap { AuthCopy.field($0, locale: locale) },
                    identifier: "sign-in.email", contentType: .username, keyboard: .emailAddress, focus: $focus
                ) {
                    focus = "sign-in.password"
                }.authMeasure(.email, report)
                AuthField(
                    copy("Password"), text: Binding(get: { model.password }, set: model.editPassword), secure: true,
                    error: model.form.fields["password"].flatMap { AuthCopy.field($0, locale: locale) },
                    identifier: "sign-in.password", contentType: .password, submitLabel: .go, focus: $focus
                ) { submit(.password) }
                .authMeasure(.password, report)
                .background {
                    AuthKeyboardReveal(
                        field: focus == "sign-in.email"
                            ? frames[.email] : focus == "sign-in.password" ? frames[.password] : nil,
                        submit: frames[.submit])
                }
                AuthButton(copy("Sign in"), kind: .outline, busy: model.form.pending == .password) { submit(.password) }
                    .accessibilityIdentifier("sign-in.submit").authMeasure(.submit, report)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        forgot.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: AuthTokens.fieldGap)
                        signup.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        forgot
                        signup
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } footer: {
                AuthButton(copy("New here? Plan a trip first"), kind: .footer, action: guest).accessibilityIdentifier(
                    "sign-in.guest")
            }
            .disabled(model.form.busy)
            .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: NSAttributedString(
                            string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true]))
                }
            }
            .authFailureFeedback(
                form: model.form, focus: $focus,
                firstInvalidField: ["email", "password"].first { model.form.fields[$0] != nil }.map { "sign-in." + $0 },
                bannerFocus: $bannerFocused
            )
            .onDisappear {
                request?.cancel()
                request = nil
                model.clearPassword()
            }
        }
        private var forgot: some View {
            link("Forgot your password?", id: "sign-in.forgot", color: .foreground) { model.navigation.forgot() }
        }
        private var signup: some View {
            link("Create an account", id: "sign-in.signup", color: .dawnText) { model.navigation.push(.signUp) }
        }
        private func link(_ key: String, id: String, color: ColorToken, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                WelcomeText(
                    copy(key), style: color == .dawnText ? Typography.authStrong : Typography.authLabel, color: color,
                    underlined: true
                )
                .authMeasure(color == .dawnText ? .signupLabel : .forgotLabel, report)
                .padding(.horizontal, AuthTokens.fieldGap)
                .frame(minHeight: AuthTokens.touch, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(id)
                .authMeasure(color == .dawnText ? .signup : .forgot, report)
        }
        private func report(_ element: AuthElement, _ rect: CGRect) {
            if frames[element] != rect { frames[element] = rect }
            measure(element, rect)
        }
        private func submit(_ action: AuthFormModel.Action) {
            guard request == nil, !model.form.busy else { return }
            request = Task {
                if action == .passkey { await model.submitPasskey() } else { await model.submitPassword() }
                request = nil
            }
        }
    }
#endif

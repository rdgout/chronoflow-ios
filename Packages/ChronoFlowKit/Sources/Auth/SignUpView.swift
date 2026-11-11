#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct SignUpView: View {
        @Environment(\.locale) private var locale
        @AccessibilityFocusState private var bannerFocused: Bool
        @FocusState private var focus: String?
        @State private var model: SignUpModel
        @State private var request: Task<Void, Never>?
        @State private var frames: [AuthElement: CGRect] = [:]
        let measure: (AuthElement, CGRect) -> Void
        let automaticallyFocusesErrors: Bool
        public init(
            model: SignUpModel, automaticallyFocusesErrors: Bool = true,
            measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }
        ) {
            _model = State(initialValue: model)
            self.measure = measure
            self.automaticallyFocusesErrors = automaticallyFocusesErrors
        }
        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }
        private func error(_ field: String) -> String? {
            model.form.fields[field].flatMap { AuthCopy.field($0, locale: locale) }
        }
        public var body: some View {
            AuthScreen(
                scrollIdentifier: "sign-up.scroll", title: copy("Create an account"),
                description: copy("Save your trips and get reminders on this phone."), compact: true, back: back,
                measure: report
            ) {
                if let banner = model.form.banner {
                    AuthBanner(title: copy(banner.title(for: .signUp)), message: copy(banner.body(for: .signUp)))
                        .id(AuthFeedbackTarget.banner).accessibilityFocused($bannerFocused)
                }
                AuthField(
                    copy("Name"), text: Binding(get: { model.name }, set: model.editName), error: error("name"),
                    identifier: "sign-up.name", contentType: .name, focus: $focus, submit: { focus = "sign-up.email" }
                ).authMeasure(.name, report)
                    .background { AuthKeyboardReveal(field: focusedFrame, submit: frames[.submit]) }
                AuthField(
                    copy("Email"), text: Binding(get: { model.email }, set: model.editEmail), error: error("email"),
                    identifier: "sign-up.email", contentType: .emailAddress, keyboard: .emailAddress, focus: $focus,
                    submit: { focus = "sign-up.password" }
                ).authMeasure(.email, report)
                AuthField(
                    copy("Password"), text: Binding(get: { model.password }, set: model.editPassword),
                    secure: !model.showsPassword, error: error("password"),
                    hint: copy(AuthPasswordPolicy.hint), identifier: "sign-up.password", contentType: .newPassword,
                    focus: $focus, submit: { focus = "sign-up.confirmation" }
                ).authMeasure(.password, report)
                AuthField(
                    copy("Confirm password"), text: Binding(get: { model.confirmation }, set: model.editConfirmation),
                    secure: !model.showsPassword,
                    error: error("password_confirmation"), identifier: "sign-up.confirmation",
                    contentType: .newPassword, submitLabel: .go, focus: $focus, submit: submit
                ).authMeasure(.confirmation, report)
                Toggle(isOn: Binding(get: { model.showsPassword }, set: { _ in model.togglePassword() })) {
                    HStack(spacing: AuthTokens.fieldGap) {
                        AuthGlyph.eye.image.resizable().frame(width: AuthTokens.icon, height: AuthTokens.icon)
                            .accessibilityHidden(true)
                        WelcomeText(
                            copy(model.showsPassword ? "Hide password" : "Show password"), style: Typography.authLabel,
                            color: .foreground)
                    }
                }.tint(ColorToken.primary.color).accessibilityLabel(Text(verbatim: copy("Show password")))
                    .accessibilityIdentifier("sign-up.visibility").frame(minHeight: AuthTokens.touch).authMeasure(
                        .visibility, report)
                AuthButton(copy("Create account"), busy: model.form.busy, action: submit).accessibilityIdentifier(
                    "sign-up.submit"
                ).authMeasure(.submit, report)
                AuthConsent(
                    text: copy(
                        "By creating an account you agree to the <terms>terms</terms> and <privacy>privacy policy</privacy>."
                    )
                )
                .accessibilityIdentifier("sign-up.consent").authMeasure(.consent, report)
            } footer: {
                AuthButton(copy("Already have an account? Sign in"), kind: .footer, action: back)
                    .accessibilityIdentifier("sign-up.back")
            }
            .disabled(model.form.busy)
            .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) { authAnnounce(message) }
            }
            .authFailureFeedback(
                form: model.form, focus: $focus, firstInvalidField: firstInvalidField, bannerFocus: $bannerFocused,
                automaticallyFocusesErrors: automaticallyFocusesErrors
            )
            .onDisappear {
                request?.cancel()
                request = nil
                model.cancel()
            }
        }
        private var firstInvalidField: String? {
            ["name", "email", "password", "password_confirmation"].first { error($0) != nil }.map {
                "sign-up." + ($0 == "password_confirmation" ? "confirmation" : $0)
            }
        }
        private var focusedFrame: CGRect? {
            switch focus {
            case "sign-up.name": frames[.name]
            case "sign-up.email": frames[.email]
            case "sign-up.password": frames[.password]
            case "sign-up.confirmation": frames[.confirmation]
            default: nil
            }
        }
        private func report(_ element: AuthElement, _ rect: CGRect) {
            if frames[element] != rect { frames[element] = rect }
            measure(element, rect)
        }
        private func submit() {
            guard request == nil, !model.form.busy else { return }
            request = Task {
                await model.submit(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                request = nil
            }
        }
        private func back() {
            request?.cancel()
            request = nil
            focus = nil
            model.backToSignIn()
        }
    }
#endif

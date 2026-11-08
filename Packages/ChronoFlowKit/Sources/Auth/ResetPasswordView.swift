#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct ResetPasswordView: View {
        @Environment(\.locale) private var locale
        @FocusState private var focus: String?
        @State private var model: ResetPasswordModel
        @State private var request: Task<Void, Never>?
        @State private var frames: [AuthElement: CGRect] = [:]
        let measure: (AuthElement, CGRect) -> Void
        public init(model: ResetPasswordModel, measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }) {
            _model = State(initialValue: model)
            self.measure = measure
        }
        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }
        public var body: some View {
            Group {
                if model.state == .expired {
                    ResetLinkExpiredView(model: model.recovery, measure: measure)
                } else {
                    AuthScreen(
                        scrollIdentifier: "reset.scroll",
                        title: copy(model.state == .done ? "Password saved" : "Choose a new password"),
                        description: copy(
                            model.state == .done
                                ? "Password updated. Sign in with your new password."
                                : "Sign in with your new password once it's saved."),
                        headingGlyph: model.state == .done ? .check : nil, back: back, measure: report
                    ) {
                        if model.state == .done {
                            WelcomeText(
                                copy(
                                    "Other devices are signed out. If you didn't make this change, reset your password again and contact us."
                                ), style: Typography.authHint, color: .mutedForeground
                            )
                            .authMeasure(.notice, report)
                            AuthButton(copy("Continue"), minimumHeight: AuthTokens.footerHeight, action: back)
                                .accessibilityIdentifier("reset.continue").authMeasure(.submit, report)
                        } else {
                            if let banner = model.form.banner {
                                AuthBanner(
                                    title: copy(banner.title(for: .reset)), message: copy(banner.body(for: .reset)))
                            }
                            AuthField(
                                copy("New password"), text: Binding(get: { model.password }, set: model.editPassword),
                                secure: true,
                                error: model.form.fields["password"].flatMap { AuthCopy.field($0, locale: locale) },
                                hint: copy(AuthPasswordPolicy.hint), identifier: "reset.password",
                                contentType: .newPassword, focus: $focus,
                                submit: { focus = "reset.confirmation" }
                            ).authMeasure(.password, report)
                            AuthField(
                                copy("Confirm new password"),
                                text: Binding(get: { model.confirmation }, set: model.editConfirmation), secure: true,
                                error: model.form.fields["password_confirmation"].flatMap {
                                    AuthCopy.field($0, locale: locale)
                                },
                                identifier: "reset.confirmation", contentType: .newPassword, submitLabel: .go,
                                focus: $focus, submit: submit
                            )
                            .authMeasure(.confirmation, report)
                            AuthButton(copy("Save new password"), busy: model.form.busy, action: submit)
                                .accessibilityIdentifier("reset.submit").authMeasure(.submit, report)
                        }
                    } footer: {
                        EmptyView()
                    }
                    .background {
                        AuthKeyboardReveal(
                            field: focus == "reset.password"
                                ? frames[.password] : focus == "reset.confirmation" ? frames[.confirmation] : nil,
                            submit: frames[.submit])
                    }
                    .disabled(model.form.busy)
                }
            }
            .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: model.form.busy) {
                if model.form.busy {
                    focus = nil
                } else if model.form.failure != nil {
                    focus =
                        model.form.fields["password_confirmation"] != nil && model.form.fields["password"] == nil
                        ? "reset.confirmation" : "reset.password"
                }
            }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) { authAnnounce(message) }
            }
            .onChange(of: model.state) {
                focus = nil
                UIAccessibility.post(notification: .screenChanged, argument: nil)
                if model.state == .done { authAnnounce(copy("Password updated. Sign in with your new password.")) }
            }
            .onDisappear {
                request?.cancel()
                request = nil
                model.cancel()
            }
        }
        private func report(_ element: AuthElement, _ rect: CGRect) {
            if frames[element] != rect { frames[element] = rect }
            measure(element, rect)
        }
        private func submit() {
            guard request == nil, !model.form.busy else { return }
            request = Task {
                await model.submit()
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

    public struct ResetLinkExpiredView: View {
        let model: ForgotPasswordModel
        let measure: (AuthElement, CGRect) -> Void
        public init(model: ForgotPasswordModel, measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }) {
            self.model = model
            self.measure = measure
        }
        public var body: some View { ForgotPasswordView(model: model, expired: true, measure: measure) }
    }

    func authAnnounce(_ message: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true]))
    }
#endif

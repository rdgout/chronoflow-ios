#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct ForgotPasswordView: View {
        @Environment(\.locale) private var locale
        @Environment(\.openURL) private var openURL
        @FocusState private var focus: String?
        @State private var model: ForgotPasswordModel
        @State private var request: Task<Void, Never>?
        @State private var frames: [AuthElement: CGRect] = [:]
        let measure: (AuthElement, CGRect) -> Void

        public init(model: ForgotPasswordModel, measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }) {
            _model = State(initialValue: model)
            self.measure = measure
        }

        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }

        public var body: some View {
            AuthScreen(
                scrollIdentifier: "forgot.scroll", title: copy("Reset your password"),
                description: copy("Enter your email and we'll send you a link to choose a new one."),
                back: back, measure: report
            ) {
                if let email = model.sentEmail {
                    AuthNotice(
                        title: copy("Check your inbox."), message: AuthCopy.resetSent(email: email, locale: locale)
                    )
                    .accessibilityIdentifier("forgot.notice").authMeasure(.notice, report)
                    AuthButton(copy("Open email app")) {
                        Task {
                            await model.openEmail { url in
                                await withCheckedContinuation { continuation in
                                    openURL(url) { continuation.resume(returning: $0) }
                                }
                            }
                        }
                    }.accessibilityIdentifier("forgot.open-email").authMeasure(.openEmail, report)
                    AuthButton(copy("Back to sign in"), kind: .ghost, action: back)
                        .accessibilityIdentifier("forgot.back").authMeasure(.backToSignIn, report)
                } else {
                    if let banner = model.form.banner {
                        AuthBanner(title: copy(banner.title(for: .forgot)), message: copy(banner.body(for: .forgot)))
                    }
                    AuthField(
                        copy("Email"), text: Binding(get: { model.email }, set: model.editEmail),
                        error: model.form.fields["email"].flatMap { AuthCopy.field($0, locale: locale) },
                        identifier: "forgot.email", contentType: .emailAddress, keyboard: .emailAddress,
                        submitLabel: .send, focus: $focus, submit: submit
                    ).authMeasure(.email, report)
                        .background {
                            AuthKeyboardReveal(
                                field: focus == "forgot.email" ? frames[.email] : nil, submit: frames[.submit])
                        }
                    AuthButton(copy("Send reset link"), busy: model.form.busy, action: submit)
                        .accessibilityIdentifier("forgot.submit").authMeasure(.submit, report)
                }
            } footer: {
                EmptyView()
            }
            .disabled(model.form.busy)
            .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: model.form.busy) {
                if model.form.busy { focus = nil } else if model.form.failure != nil { focus = "forgot.email" }
            }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) { announce(message) }
            }
            .onChange(of: model.sentEmail) {
                guard let email = model.sentEmail else { return }
                focus = nil
                UIAccessibility.post(notification: .screenChanged, argument: nil)
                announce(copy("Check your inbox.") + " " + AuthCopy.resetSent(email: email, locale: locale))
            }
            .onDisappear {
                request?.cancel()
                request = nil
                model.cancel()
            }
        }

        private func announce(_ message: String) {
            UIAccessibility.post(
                notification: .announcement,
                argument: NSAttributedString(string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true])
            )
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
#endif

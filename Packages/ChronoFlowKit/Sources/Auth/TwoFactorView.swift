#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct TwoFactorView: View {
        @Environment(\.locale) private var locale
        @FocusState private var focus: String?
        @State private var text: String
        @State private var request: Task<Void, Never>?
        @State private var frames: [AuthElement: CGRect] = [:]
        let model: TwoFactorModel
        let measure: (AuthElement, CGRect) -> Void

        public init(model: TwoFactorModel, measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }) {
            self.model = model
            _text = State(initialValue: model.code)
            self.measure = measure
        }

        private var identifier: String { "two-factor.\(model.field)" }
        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }

        public var body: some View {
            AuthScreen(
                title: copy("Enter your code"),
                description: copy("Open your authenticator app and type the 6-digit code for ChronoFlow."),
                back: cancel, measure: report
            ) {
                Group {
                    if let banner = model.form.banner {
                        AuthBanner(title: copy(banner.title), message: copy(banner.body(for: .twoFactor)))
                    }
                    AuthField(
                        copy(model.mode == .code ? "6-digit code" : "Recovery code"),
                        text: $text,
                        error: model.form.fields[model.field].flatMap { AuthCopy.field($0, locale: locale) },
                        hint: model.mode == .recovery ? copy("Each recovery code works once.") : nil,
                        identifier: identifier, contentType: model.mode == .code ? .oneTimeCode : nil,
                        keyboard: model.mode == .code ? .numberPad : .default, submitLabel: .go, focus: $focus,
                        submit: submit
                    )
                    .id(model.mode).authMeasure(.code, report)
                    .background {
                        AuthKeyboardReveal(field: focus == identifier ? frames[.code] : nil, submit: frames[.submit])
                    }
                    AuthButton(copy("Verify"), busy: model.form.pending == .verify, action: submit)
                        .accessibilityIdentifier("two-factor.submit").authMeasure(.submit, report)
                    AuthButton(
                        copy(model.mode == .code ? "Use a recovery code instead" : "Use your authenticator app"),
                        kind: .ghost
                    ) {
                        focus = nil
                        model.toggleMode()
                    }.accessibilityIdentifier("two-factor.toggle").authMeasure(.modeToggle, report)
                }.disabled(model.form.busy)
            } footer: {
                EmptyView()
            }
            .onAppear {
                model.validateChallenge()
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
            .onChange(of: text) {
                guard text != model.code else { return }
                model.editCode(text)
                text = model.code
            }
            .onChange(of: model.code) { text = model.code }
            .onChange(of: model.form.busy) {
                if model.form.busy {
                    focus = nil
                } else if model.form.failure != nil || model.sessionFailure != nil {
                    focus = identifier
                }
            }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: NSAttributedString(
                            string: message, attributes: [.accessibilitySpeechQueueAnnouncement: true]))
                }
            }
            .onDisappear(perform: cancel)
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

        private func cancel() {
            request?.cancel()
            request = nil
            focus = nil
            model.cancel()
        }
    }
#endif

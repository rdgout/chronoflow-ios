#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct GuestSignupView: View {
        @Environment(\.locale) private var locale
        @FocusState private var focus: String?
        @AccessibilityFocusState private var bannerFocused: Bool
        @State private var model: SignUpModel
        @State private var request: Task<Void, Never>?
        let signIn: () -> Void
        let review: () -> Void

        public init(model: SignUpModel, signIn: @escaping () -> Void, review: @escaping () -> Void) {
            _model = State(initialValue: model)
            self.signIn = signIn
            self.review = review
        }

        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }
        private func error(_ field: String) -> String? {
            model.form.fields[field].flatMap { AuthCopy.field($0, locale: locale) }
        }

        public var body: some View {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                        VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                            WelcomeText(copy("Save your plan"), style: Typography.screenCardTitle, color: .foreground)
                                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("guest-signup.title")
                            Text(copy("Create an account to save it and open it on any device."))
                                .font(Typography.screenBodyLg.font).foregroundStyle(ColorToken.mutedForeground.color)
                        }
                        if let title = model.guestState.title, let message = model.guestState.message {
                            AuthBanner(
                                title: copy(title), message: copy(message),
                                actionTitle: model.guestState == .review ? copy("Review my trip") : nil,
                                action: model.guestState == .review ? review : nil
                            )
                            .id(AuthFeedbackTarget.banner).accessibilityFocused($bannerFocused)
                        }
                        VStack(spacing: PlanUITokens.space3) {
                            AuthField(
                                copy("Name"), text: Binding(get: { model.name }, set: model.editName),
                                error: error("name"), identifier: "guest-signup.name", contentType: .name,
                                focus: $focus, submit: { focus = "guest-signup.email" })
                            AuthField(
                                copy("Email"), text: Binding(get: { model.email }, set: model.editEmail),
                                error: error("email"), identifier: "guest-signup.email", contentType: .emailAddress,
                                keyboard: .emailAddress, focus: $focus, submit: { focus = "guest-signup.password" })
                            AuthField(
                                copy("Password"), text: Binding(get: { model.password }, set: model.editPassword),
                                secure: true, error: error("password"), hint: copy(AuthPasswordPolicy.hint),
                                identifier: "guest-signup.password", contentType: .newPassword,
                                focus: $focus, submit: { focus = "guest-signup.confirmation" })
                            AuthField(
                                copy("Confirm password"),
                                text: Binding(get: { model.confirmation }, set: model.editConfirmation),
                                secure: true, error: error("password_confirmation"),
                                identifier: "guest-signup.confirmation", contentType: .newPassword,
                                submitLabel: .go, focus: $focus, submit: submit)
                        }
                        VStack(spacing: PlanUITokens.space2) {
                            AuthButton(copy("Create account and save"), busy: model.form.busy, action: submit)
                                .disabled(model.guestState == .review).accessibilityIdentifier("guest-signup.submit")
                            AuthButton(copy("I already have an account"), kind: .ghost, action: signIn)
                                .accessibilityIdentifier("guest-signup.sign-in")
                        }
                        AuthConsent(
                            text: copy(
                                "By creating an account you accept the <terms>terms</terms> and <privacy>privacy policy</privacy>."
                            )
                        )
                        .accessibilityIdentifier("guest-signup.consent")
                    }.padding(.horizontal, PlanUITokens.space5).padding(.top, PlanUITokens.space5)
                        .padding(.bottom, PlanUITokens.space8).frame(maxWidth: PlanUITokens.wizardColumnWidth)
                        .frame(maxWidth: .infinity)
                }.accessibilityIdentifier("guest-signup.scroll")
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.guestState) { _, state in
                        guard let title = state.title, let message = state.message else { return }
                        focus = nil
                        scroll.scrollTo(AuthFeedbackTarget.banner, anchor: .top)
                        bannerFocused = true
                        authAnnounce(copy(title) + " " + copy(message))
                    }
            }
            .authFailureFeedback(
                form: model.form, focus: $focus, firstInvalidField: firstInvalidField,
                bannerFocus: $bannerFocused
            )
            .disabled(model.form.busy)
            .onChange(of: model.form.announcementRevision) {
                if model.guestState == .ready, let message = model.form.takeAnnouncement(locale: locale) {
                    authAnnounce(message)
                }
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(PlanUITokens.wizardSheetRadius).presentationBackground(ColorToken.card.color)
            .interactiveDismissDisabled(model.form.busy)
            .onDisappear {
                request?.cancel()
                model.cancel()
            }
        }

        private var firstInvalidField: String? {
            ["name", "email", "password", "password_confirmation"].first { error($0) != nil }.map {
                "guest-signup." + ($0 == "password_confirmation" ? "confirmation" : $0)
            }
        }

        private func submit() {
            guard request == nil, !model.form.busy, model.guestState != .review else { return }
            focus = nil
            request = Task {
                await model.submit(
                    language: locale.language.languageCode?.identifier == "nl" ? .nl : .en,
                    requiresGuestClaim: true)
                request = nil
            }
        }
    }
#endif

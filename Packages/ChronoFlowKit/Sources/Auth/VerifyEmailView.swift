#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public struct VerifyEmailView: View {
        @Environment(\.locale) private var locale
        @AccessibilityFocusState private var bannerFocused: Bool
        @Environment(\.openURL) private var openURL
        @Environment(\.scenePhase) private var scenePhase
        @State private var model: VerifyEmailModel
        @State private var request: Task<Void, Never>?
        let measure: (AuthElement, CGRect) -> Void
        let automaticallyChecks: Bool
        public init(
            model: VerifyEmailModel, automaticallyChecks: Bool = true,
            measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in }
        ) {
            _model = State(initialValue: model)
            self.measure = measure
            self.automaticallyChecks = automaticallyChecks
        }
        private var failed: Bool { model.state == .failed }
        private func copy(_ key: String) -> String { AuthCopy.string(key, locale: locale) }
        private var signOutError: String? {
            model.signOutFailure.map { copy($0 == .offline ? "Needs a connection" : "Something went wrong") }
        }
        public var body: some View {
            AuthScreen(
                scrollIdentifier: "verify.scroll",
                title: copy(failed ? "We couldn't check your email" : "Check your inbox"),
                description: failed
                    ? copy("The link may have expired, or we couldn't reach the server.")
                    : AuthCopy.verificationSent(email: model.context.email, locale: locale),
                headingGlyph: failed ? .problem : nil, back: signOut, measure: measure
            ) {
                if let signOutError {
                    WelcomeText(signOutError, style: Typography.authBody, color: .destructive)
                        .accessibilityIdentifier("verify.sign-out-error")
                        .id(AuthFeedbackTarget.banner).accessibilityFocused($bannerFocused)
                } else if let banner = model.form.banner {
                    AuthBanner(title: copy(banner.title(for: .verify)), message: copy(banner.body(for: .verify)))
                        .id(AuthFeedbackTarget.banner).accessibilityFocused($bannerFocused)
                }
                if failed {
                    AuthButton(
                        copy("Try again"), busy: model.form.pending == .checkVerification,
                        minimumHeight: AuthTokens.footerHeight
                    ) {
                        run { await model.check() }
                    }
                    .accessibilityIdentifier("verify.retry").authMeasure(.submit, measure)
                    AuthButton(
                        copy("Send a new link"), kind: .outline, busy: model.form.pending == .resendVerification,
                        minimumHeight: AuthTokens.footerHeight
                    ) { run { await model.resend() } }
                    .disabled(!model.canResend).accessibilityIdentifier("verify.resend").authMeasure(.resend, measure)
                } else {
                    VStack(spacing: AuthTokens.fieldGap) {
                        AuthButton(copy("Open email app")) {
                            run {
                                await model.openEmail { url in
                                    await withCheckedContinuation { continuation in
                                        openURL(url) { continuation.resume(returning: $0) }
                                    }
                                }
                            }
                        }.accessibilityIdentifier("verify.open-email").authMeasure(.submit, measure)
                        AuthButton(copy("Resend link"), kind: .outline, busy: model.form.pending == .resendVerification)
                        { run { await model.resend() } }
                        .disabled(!model.canResend).accessibilityIdentifier("verify.resend").authMeasure(
                            .resend, measure)
                    }
                    if model.remaining > 0 {
                        WelcomeText(
                            AuthCopy.resendCountdown(seconds: model.remaining, locale: locale),
                            style: Typography.authHint, color: .mutedForeground
                        )
                        .monospacedDigit().multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("verify.countdown").authMeasure(.notice, measure)
                    }
                    AuthButton(copy("Use a different email"), kind: .ghost, action: signOut).accessibilityIdentifier(
                        "verify.different-email"
                    ).authMeasure(.backToSignIn, measure)
                }
            } footer: {
                EmptyView()
            }
            .disabled(model.form.busy)
            .task {
                guard automaticallyChecks else { return }
                await model.activate()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    model.tick()
                }
            }
            .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: scenePhase) { if scenePhase == .active { run { await model.activate() } } }
            .onChange(of: model.state) { UIAccessibility.post(notification: .screenChanged, argument: nil) }
            .onChange(of: model.form.announcementRevision) {
                if let message = model.form.takeAnnouncement(locale: locale) { authAnnounce(signOutError ?? message) }
            }
            .authFailureFeedback(form: model.form, bannerFocus: $bannerFocused)
            .onDisappear {
                request?.cancel()
                request = nil
                model.cancel()
            }
        }
        private func run(_ action: @escaping @MainActor () async -> Void) {
            guard request == nil, !model.form.busy else { return }
            request = Task {
                await action()
                request = nil
            }
        }
        private func signOut() { run { await model.signOut() } }
    }
#endif

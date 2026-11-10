import Auth
import DesignSystem
import SwiftUI
import TripWizard
import TripWizardUI

struct GuestWizardDestination: View {
    @Environment(\.locale) private var locale
    let services: AuthSessionServices
    let navigator: RootNavigator
    @State private var wizard: MemberWizardModel?
    @State private var signup: SignupPresentation?

    private struct SignupPresentation: Identifiable {
        let id = UUID()
        let model: SignUpModel
    }

    var body: some View {
        Group {
            if let wizard {
                MemberWizardView(model: wizard, signUpRequested: { presentSignup(wizard) }) {
                    Task {
                        if let token = wizard.draft.form.identity?.token {
                            try? await services.nativeSession.guestSecrets.delete(for: token)
                        }
                        navigator.navigate(to: .welcome)
                    }
                }
            } else {
                ColorToken.background.color.ignoresSafeArea()
            }
        }
        .sheet(item: $signup) { presentation in
            GuestSignupView(
                model: presentation.model,
                signIn: {
                    presentation.model.backToSignIn()
                    services.model.clearSecrets()
                    services.model.editEmail(presentation.model.email)
                    signup = nil
                    navigator.navigate(to: .signIn)
                },
                review: {
                    wizard?.guestReviewExpired()
                    signup = nil
                }
            )
            .onDisappear { signupDismissed(presentation.model) }
        }
        .task {
            guard wizard == nil else { return }
            do {
                wizard = try await services.makeGuestWizard(locale: locale)
                #if DEBUG
                    if services.authUITestEnabled,
                        UITestRuntime.environment["CF_WIZARD_BOARD_CAPTURE"]?.hasPrefix("GuestSignup") == true,
                        let wizard
                    {
                        presentSignup(wizard)
                    }
                #endif
            } catch is CancellationError { return } catch {
                assertionFailure("Guest wizard start failed: \(error)")
                navigator.navigate(to: .welcome)
            }
        }
    }

    private func presentSignup(_ wizard: MemberWizardModel) {
        guard signup == nil, !wizard.guestAuthenticationPresented else { return }
        wizard.setGuestAuthenticationPresented(true)
        Task {
            await wizard.flush()
            guard !Task.isCancelled, !wizard.closed, !wizard.persistenceFailed else {
                wizard.setGuestAuthenticationPresented(false)
                return
            }
            let signup = services.model.makeSignUpModel()
            #if DEBUG
                if services.authUITestEnabled,
                    let board = UITestRuntime.environment["CF_WIZARD_BOARD_CAPTURE"]
                {
                    let state: GuestSignupState =
                        [
                            "GuestSignupFailed": .failed, "GuestSignupRetry": .retry, "GuestSignupReview": .review,
                        ][board] ?? .ready
                    signup.seedGuestSignupState(state)
                }
            #endif
            self.signup = SignupPresentation(model: signup)
        }
    }

    private func signupDismissed(_ signup: SignUpModel) {
        let needsReview = signup.guestState == .review
        signup.cancel()
        wizard?.setGuestAuthenticationPresented(false)
        guard navigator.route == .guestWizard else { return }
        if needsReview { wizard?.guestReviewExpired() }
        wizard?.readyTick()
    }
}

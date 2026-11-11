import AppCore
import Auth
import SwiftUI

#if DEBUG
    import DataAccess
#endif

struct AuthRootView: View {
    let model: SignInModel
    let back: () -> Void
    let guest: () -> Void

    var body: some View {
        @Bindable var navigation = model.navigation
        NavigationStack(path: $navigation.path) {
            SignInView(model: model, back: back, guest: guest)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AuthDestination.self) { destination in
                    if case .reset(let link) = destination {
                        ResetPasswordView(
                            model: resetModel(link), automaticallyFocusesErrors: automaticallyFocusesErrors
                        ).toolbar(
                            .hidden, for: .navigationBar)
                    } else if destination == .signUp {
                        SignUpView(model: signUpModel(), automaticallyFocusesErrors: automaticallyFocusesErrors)
                            .toolbar(.hidden, for: .navigationBar)
                    } else if destination == .forgot {
                        ForgotPasswordView(model: model.makeForgotPasswordModel()).toolbar(.hidden, for: .navigationBar)
                    } else if destination == .twoFactor {
                        if let twoFactor = model.twoFactor, navigation.challengeID != nil {
                            TwoFactorView(model: twoFactor).toolbar(.hidden, for: .navigationBar)
                        } else {
                            EmptyView().onAppear { navigation.cancelTwoFactor() }
                        }
                    } else {
                        seam(destination)
                    }
                }
        }
        .onDisappear { model.clearSecrets() }
    }

    private var automaticallyFocusesErrors: Bool {
        #if DEBUG
            AuthUITestConfiguration(environment: UITestRuntime.environment)?.auditState == nil
        #else
            true
        #endif
    }

    private func signUpModel() -> SignUpModel {
        let result = model.makeSignUpModel()
        #if DEBUG
            AuthUITestConfiguration(environment: UITestRuntime.environment)?.prefill(result)
        #endif
        return result
    }

    private func resetModel(_ link: ResetPasswordLink) -> ResetPasswordModel {
        let result = model.makeResetPasswordModel(link)
        #if DEBUG
            AuthUITestConfiguration(environment: UITestRuntime.environment)?.prefill(result)
        #endif
        return result
    }

    @ViewBuilder private func seam(_ destination: AuthDestination) -> some View {
        #if DEBUG
            Text(String(format: String(localized: "Debug route: %@"), String(describing: destination)))
                .accessibilityIdentifier("route.\(destination)")
        #else
            EmptyView()
        #endif
    }
}

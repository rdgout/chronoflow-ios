import Auth
import SwiftUI

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
                    if destination == .twoFactor {
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

    @ViewBuilder private func seam(_ destination: AuthDestination) -> some View {
        #if DEBUG
            Text(String(format: String(localized: "Debug route: %@"), String(describing: destination)))
                .accessibilityIdentifier("route.\(destination)")
        #else
            EmptyView()
        #endif
    }
}

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
                    seam(destination).onDisappear {
                        if destination == .twoFactor { navigation.discardChallenge() }
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

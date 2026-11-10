import DesignSystem
import SwiftUI
import TripWizard
import TripWizardUI

struct GuestWizardDestination: View {
    @Environment(\.locale) private var locale
    let services: AuthSessionServices
    let navigator: RootNavigator
    @State private var wizard: MemberWizardModel?

    var body: some View {
        Group {
            if let wizard {
                MemberWizardView(model: wizard) {
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
        .task {
            guard wizard == nil else { return }
            do {
                wizard = try await services.makeGuestWizard(locale: locale)
            } catch is CancellationError { return } catch {
                assertionFailure("Guest wizard start failed: \(error)")
                navigator.navigate(to: .welcome)
            }
        }
    }
}

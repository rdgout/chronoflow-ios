import AppCore
import Auth
import DesignSystem
import Observation
import SwiftUI
import Welcome

@Observable
final class RootNavigator: Navigator {
    private(set) var revision: UInt64 = 0
    private(set) var route: Route?

    init(route: Route? = nil) {
        self.route = route
    }

    func navigate(to route: Route) {
        revision &+= 1
        self.route = route
    }
}

struct RootView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var navigator = RootNavigator()
    var authModel: SignInModel?
    var moonAnchorStore: MoonAnchorStore?
    var launchIntro: LaunchIntro?
    var forcesReduceMotion = false

    var body: some View {
        content.dynamicTypeSize(...ContentSizeCap.maximum)
            .environment(\.dynamicTypeSize, ContentSizeCap.clamp(dynamicTypeSize))
    }

    @ViewBuilder private var content: some View {
        if let route = navigator.route {
            if route == .welcome {
                WelcomeView()
                    .environment(\.welcomeNavigator, navigator)
                    .environment(\.moonAnchorStore, moonAnchorStore)
                    .environment(\.launchIntro, launchIntro)
                    .environment(\.forcesReduceMotion, forcesReduceMotion)
            } else if route == .signIn, let authModel {
                AuthRootView(
                    model: authModel, back: { navigator.navigate(to: .welcome) },
                    guest: { navigator.navigate(to: .guestWizard) })
            } else {
                #if DEBUG
                    RoutePlaceholder(route: route)
                #else
                    EmptyView()
                #endif
            }
        }
    }
}

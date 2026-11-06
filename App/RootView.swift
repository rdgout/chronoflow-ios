import AppCore
import DesignSystem
import Observation
import SwiftUI
import Welcome

@Observable
final class RootNavigator: Navigator {
    private(set) var route: Route?

    init(route: Route? = nil) {
        self.route = route
    }

    func navigate(to route: Route) {
        self.route = route
    }
}

struct RootView: View {
    var navigator = RootNavigator()
    var moonAnchorStore: MoonAnchorStore?

    var body: some View {
        content.dynamicTypeSize(...ContentSizeCap.maximum)
    }

    @ViewBuilder private var content: some View {
        if let route = navigator.route {
            if route == .welcome {
                WelcomeView()
                    .environment(\.moonAnchorStore, moonAnchorStore)
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

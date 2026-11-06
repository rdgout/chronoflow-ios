import AppCore
import Observation
import SwiftUI

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

    var body: some View {
        if let route = navigator.route {
            #if DEBUG
                RoutePlaceholder(route: route)
            #else
                EmptyView()
            #endif
        }
    }
}

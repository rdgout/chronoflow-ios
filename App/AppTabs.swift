import AppCore
import SwiftUI

struct AppTabs: View {
    enum Tab: Hashable { case today, trips, settings }
    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { seam(.today) }
                .tabItem { Label(String(localized: "Today"), systemImage: "sun.max") }
                .tag(Tab.today)
            NavigationStack { seam(.trips) }
                .tabItem { Label(String(localized: "My trips"), systemImage: "airplane") }
                .tag(Tab.trips)
            NavigationStack { seam(.settings) }
                .tabItem { Label(String(localized: "Settings"), systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .accessibilityIdentifier("app.tabs")
    }

    @ViewBuilder private func seam(_ route: Route) -> some View {
        #if DEBUG
            RoutePlaceholder(route: route)
        #else
            EmptyView()
        #endif
    }
}

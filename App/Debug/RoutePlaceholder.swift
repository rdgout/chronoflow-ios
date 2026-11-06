#if DEBUG
    import AppCore
    import SwiftUI

    struct RoutePlaceholder: View {
        let route: Route

        var body: some View {
            Text(String(format: String(localized: "Debug route: %@"), route.rawValue))
                .accessibilityIdentifier("route.\(route.rawValue)")
        }
    }
#endif

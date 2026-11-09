import SwiftUI

struct TripPageRoute: Hashable {
    var tripID: String
    var dayID: String? = nil
    var blockID: String? = nil
    var awaitingSync = false
}

struct TripPageDestination: View {
    let route: TripPageRoute
    var native: NativeSessionController? = nil
    var body: some View {
        #if DEBUG
            Text(String(format: String(localized: "Debug route: %@"), "trip/\(route.tripID)"))
                .accessibilityIdentifier("trip.destination")
                .accessibilityValue(route.tripID)
        #else
            EmptyView()
        #endif
    }
}

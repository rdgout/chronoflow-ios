import AppCore
import DesignSystem
import SwiftUI

extension View {
    /// The trip page's bar before its model exists, so the header doesn't pop in once the plan loads.
    public func tripPageLoadingBar() -> some View { modifier(TripPageLoadingBar()) }
}

private struct TripPageLoadingBar: ViewModifier {
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        let copy = PageCopy(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        content.toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: copy("Loading your plan")).font(Typography.planTitle.font).lineLimit(1)
                    .accessibilityIdentifier("trip.loadingTitle")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(copy("Trip actions"), systemImage: "ellipsis") {}.disabled(true)
            }
        }
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

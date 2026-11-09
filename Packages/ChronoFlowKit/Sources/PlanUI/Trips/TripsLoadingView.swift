#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    public struct TripsLoadingView: View {
        @Environment(\.locale) private var locale
        public init() {}
        public var body: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space4) {
                heading
                RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                    .frame(height: PlanUITokens.tripsLoadingFirstHeight)
                heading
                RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                    .frame(height: PlanUITokens.tripsLoadingSecondHeight)
            }.foregroundStyle(ColorToken.muted.color)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    PlanStrings.text(
                        "Loading your trips", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                )
                .accessibilityAddTraits(.updatesFrequently).accessibilityIdentifier("trips.loading")
        }
        private var heading: some View {
            GeometryReader { geometry in
                Capsule().frame(width: geometry.size.width * PlanUITokens.loadingHeadingWidthRatio)
            }.frame(height: PlanUITokens.loadingHeadingHeight)
        }
    }
#endif

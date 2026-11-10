import DesignSystem
import PlanCore
import SwiftUI

struct WidePlanSkeleton: View {
    let copy: PageCopy
    let listWidth: Double

    var body: some View {
        VStack(spacing: PlanMetrics.blockIcon) {
            HStack(spacing: PlanMetrics.rowGap) {
                ProgressView().controlSize(.small)
                Text(verbatim: copy("Downloading this trip’s plan…")).font(Typography.authHint.font)
                    .foregroundStyle(ColorToken.mutedForeground.color)
            }
            HStack(spacing: PlanMetrics.rowGap) {
                ForEach(0..<4) { _ in
                    Capsule().fill(ColorToken.muted.color)
                        .frame(width: PlanMetrics.wideSkeletonPillWidth, height: PlanMetrics.touch)
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).fill(ColorToken.muted.color)
                .frame(height: PlanMetrics.wideSkeletonDayHeight)
            HStack(alignment: .top, spacing: PlanMetrics.wideColumnGap) {
                HStack(alignment: .top, spacing: PlanMetrics.laneGap) {
                    Color.clear.frame(width: PlanMetrics.gutterWidth)
                    ForEach(0..<4) { lane in
                        let heights = [
                            PlanMetrics.skeletonSummary, PlanMetrics.wideSkeletonLightHeight,
                            PlanMetrics.prioritySampleWidth, PlanMetrics.wideSkeletonTravelHeight,
                        ]
                        let offsets = [
                            0, PlanMetrics.wideSkeletonLightOffset, PlanMetrics.wideSkeletonCaffeineOffset,
                            PlanMetrics.wideSkeletonTravelOffset,
                        ]
                        ColorToken.surface2.color.overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: PlanMetrics.textPlateRadius).fill(ColorToken.muted.color)
                                .frame(height: heights[lane]).padding(.horizontal, PlanMetrics.smallGap)
                                .padding(.top, offsets[lane])
                        }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: PlanMetrics.wideSkeletonHeight)
                .planContentBounds(identifier: "trip.wide.loading.timeline")
                VStack(spacing: PlanMetrics.rowGap) {
                    ForEach(0..<5) { _ in
                        RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).fill(ColorToken.muted.color)
                            .frame(height: PlanMetrics.tinyTileHeight)
                    }
                }.frame(width: listWidth)
                    .planContentBounds(identifier: "trip.wide.loading.list")
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(copy("Downloading this trip’s plan…"))
        .accessibilityIdentifier("trip.wide.loading")
    }
}

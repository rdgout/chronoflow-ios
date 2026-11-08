#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    struct DayStatusPill: View {
        let status: DayStatus
        let text: String
        private var adapted: Bool { status == .adapted || status == .adaptedSlowerClock }
        var body: some View {
            HStack(spacing: PlanUITokens.space1) {
                if adapted { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(text).planTextStyle(
                    Typography.screenMeta,
                    color: adapted ? .dawnForeground : status == .partiallyAdapted ? .secondaryForeground : .dawnText)
            }.font(Typography.screenMeta.font)
                .padding(.horizontal, PlanUITokens.space2).padding(.vertical, PlanUITokens.space1 / 2)
                .foregroundStyle(
                    (adapted
                        ? ColorToken.dawnForeground : status == .partiallyAdapted ? .secondaryForeground : .dawnText)
                        .color
                )
                .background {
                    if adapted || status == .partiallyAdapted {
                        Capsule().fill((adapted ? ColorToken.dawn : .secondary).color)
                    }
                }
                .overlay {
                    if status == .adapting {
                        Capsule().strokeBorder(
                            ColorToken.dawn.color.opacity(PlanUITokens.statusBorderOpacity),
                            lineWidth: AuthTokens.borderWidth)
                    }
                }
        }
    }

    struct DayProgressRow: View {
        let done: Int
        let total: Int
        let skipped: Int
        let language: Language
        private var summary: String {
            PlanStrings.text(
                "{{done}} of {{total}} done", language: language,
                ["done": String(done), "total": String(total)])
                + (skipped > 0
                    ? ", " + PlanStrings.text("{{count}} skipped", language: language, count: skipped) : "")
        }
        var body: some View {
            PlanFlowRow(spacing: PlanUITokens.space2) {
                ProgressView(value: Double(done), total: Double(total))
                    .progressViewStyle(.linear).tint(ColorToken.dawn.color)
                    .frame(width: PlanUITokens.progressTrackWidth)
                    .accessibilityHidden(true)
                HStack(spacing: PlanUITokens.space2) {
                    Image(systemName: "checkmark")
                    Text(
                        PlanStrings.text(
                            "{{done}}/{{total}} done", language: language,
                            ["done": String(done), "total": String(total)]))
                }.accessibilityHidden(true)
                if skipped > 0 {
                    Text(PlanStrings.text("{{count}} skipped", language: language, count: skipped))
                }
            }.font(Typography.screenMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
                .accessibilityRepresentation {
                    Text(summary).frame(minHeight: AuthTokens.touch).accessibilityIdentifier("today.progress")
                }
        }
    }

    private struct PlanFlowRow: Layout {
        let spacing: CGFloat
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            arrange(width: proposal.width, subviews: subviews).size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let layout = arrange(width: bounds.width, subviews: subviews)
            for (index, subview) in subviews.enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + layout.points[index].x, y: bounds.minY + layout.points[index].y),
                    proposal: ProposedViewSize(layout.sizes[index]))
            }
        }
        private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, points: [CGPoint], sizes: [CGSize])
        {
            let limit = width ?? .infinity
            var points: [CGPoint] = []
            var sizes: [CGSize] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var usedWidth: CGFloat = 0
            var rowStart = 0
            for view in subviews {
                let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
                if x > 0 && x + size.width > limit {
                    for index in rowStart..<points.count {
                        points[index].y += (rowHeight - sizes[index].height) / 2
                    }
                    rowStart = points.count
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                points.append(CGPoint(x: x, y: y))
                sizes.append(size)
                usedWidth = max(usedWidth, x + size.width)
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            for index in rowStart..<points.count {
                points[index].y += (rowHeight - sizes[index].height) / 2
            }
            return (CGSize(width: usedWidth, height: y + rowHeight), points, sizes)
        }
    }
#endif

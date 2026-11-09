import AppCore
import DesignSystem
import PlanCore
import SwiftUI

struct DayHeader: View {
    let day: PreparedDay
    let copy: PageCopy
    @State private var expanded = false
    @State private var notesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    heading
                    Spacer(minLength: PlanMetrics.smallGap)
                    zone
                }
                VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                    heading
                    zone
                }
            }
            if day.warningCount > 0 {
                Button {
                    expanded.toggle()
                } label: {
                    Label(copy.count("%lld warnings", day.warningCount), systemImage: "exclamationmark.triangle")
                }.tint(ColorToken.dawnText.color)
            }
            if expanded {
                if let status = day.status {
                    Text(verbatim: status).font(Typography.authStrong.font).foregroundStyle(ColorToken.dawnText.color)
                }
                Text(verbatim: day.summary).font(Typography.planSubtitle.font).monospacedDigit()
                Text(verbatim: day.progress).font(Typography.planSubtitle.font)
                if let headline = day.headline {
                    Text(verbatim: headline).font(Typography.planSubtitle.font).foregroundStyle(
                        ColorToken.dawnText.color)
                }
                if day.warningCount == 0 && !day.notices.isEmpty {
                    Button(copy.count("%lld notes", day.notices.count)) { notesExpanded.toggle() }.font(
                        Typography.authMeta.font)
                }
                ForEach(
                    Array(day.shownNotices(expanded: expanded, notesOpen: notesExpanded).enumerated()), id: \.offset
                ) { _, notice in
                    DayNotice(notice: notice)
                }
            }
            Button(copy(expanded ? "Show less" : "Show more"), systemImage: expanded ? "chevron.up" : "chevron.down") {
                expanded.toggle()
            }
            .font(Typography.planSubtitle.font).frame(maxWidth: .infinity, minHeight: PlanMetrics.touch)
            .accessibilityValue(expanded ? copy("Show less") : copy("Show more"))
        }.foregroundStyle(ColorToken.foreground.color).padding(.vertical, PlanMetrics.rowGap)
            .background(ColorToken.background.color)
    }

    private var heading: some View {
        (Text(verbatim: day.title).font(Typography.planDayTitle.font)
            + Text(verbatim: " · " + day.date).font(Typography.planListLine.font).foregroundColor(
                ColorToken.mutedForeground.color))
            .accessibilityAddTraits(.isHeader)
    }
    private var zone: some View {
        Text(verbatim: day.zone).font(Typography.planSubtitle.font).padding(PlanMetrics.smallGap)
            .background(ColorToken.muted.color, in: Capsule())
    }
}

private struct DayNotice: View {
    let notice: PreparedNotice
    var body: some View {
        HStack(alignment: .top, spacing: PlanMetrics.sectionGap) {
            Image(systemName: notice.warning ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(notice.warning ? ColorToken.dawnText.color : ColorToken.mutedForeground.color)
                .frame(width: PlanMetrics.icon, height: PlanMetrics.icon).accessibilityHidden(true)
            Text(verbatim: notice.text).font(Typography.planListLine.font).frame(
                maxWidth: .infinity, alignment: .leading)
        }.padding(PlanMetrics.sectionGap)
            .background(
                notice.warning ? ColorToken.dawn.color.opacity(PlanMetrics.warningOpacity) : ColorToken.card.color,
                in: RoundedRectangle(cornerRadius: PlanMetrics.rowRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).strokeBorder(
                    notice.warning ? ColorToken.dawn.color.opacity(PlanMetrics.tagOpacity) : ColorToken.border.color,
                    lineWidth: PlanMetrics.border)
            )
            .accessibilityElement(children: .combine)
    }
}

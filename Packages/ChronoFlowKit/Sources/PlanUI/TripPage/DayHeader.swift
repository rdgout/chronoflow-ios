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
                    notesExpanded = expanded
                } label: {
                    Label(copy("%@ warnings", String(day.warningCount)), systemImage: "exclamationmark.triangle")
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
                if !day.notices.isEmpty {
                    Button(copy("%@ notes", String(day.notices.count))) { notesExpanded.toggle() }.font(
                        Typography.authMeta.font)
                }
                if notesExpanded {
                    ForEach(Array(day.notices.enumerated()), id: \.offset) { _, text in
                        Text(verbatim: text).font(Typography.planListLine.font).padding(PlanMetrics.rowGap)
                            .frame(maxWidth: .infinity, alignment: .leading).background(
                                ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanMetrics.rowRadius))
                    }
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

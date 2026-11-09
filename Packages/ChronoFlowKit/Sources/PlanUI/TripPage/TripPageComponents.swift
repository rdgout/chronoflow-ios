import AppCore
import DesignSystem
import PlanCore
import SwiftUI

struct DualClocks: View {
    let from: AirportRef
    let to: AirportRef
    let now: Date
    let formatter: CopyLineFormatter
    let options: CopyFormat
    let activeZone: String?
    var remote = false
    var body: some View {
        let copy = PageCopy(language: options.language)
        HStack(spacing: PlanMetrics.rowGap) {
            ForEach(Array([from, to].enumerated()), id: \.offset) { index, place in
                let active = place.zone == activeZone && (index == 0 || from.zone != to.zone)
                VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                    Text(
                        verbatim: copy(
                            remote
                                ? (index == 0 ? "Home · %@" : "There · %@")
                                : active ? "You’re here · %@" : index == 0 ? "Home time · %@" : "Destination time · %@",
                            place.city ?? place.iata)
                    )
                    .font(Typography.planSubtitle.font).foregroundStyle(
                        active ? ColorToken.dawnText.color : ColorToken.mutedForeground.color)
                    Text(verbatim: formatter.formatInstant(now.ISO8601Format(), options: options, zone: place.zone))
                        .font(Typography.planTitle.font).monospacedDigit()
                }.padding(PlanMetrics.sectionGap).frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        active ? ColorToken.card.color : ColorToken.surface2.color,
                        in: RoundedRectangle(cornerRadius: PlanMetrics.rowRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).strokeBorder(
                            active ? ColorToken.dawn.color : ColorToken.surface2.color,
                            lineWidth: PlanMetrics.emphasisBorder))
            }
        }
    }
}

public struct EndOfPlanCard: View {
    let plan: PreparedPlan
    let copy: PageCopy
    let select: (String) -> Void
    public init(plan: PreparedPlan, copy: PageCopy, select: @escaping (String) -> Void = { _ in }) {
        self.plan = plan
        self.copy = copy
        self.select = select
    }
    public var body: some View {
        PlanCard {
            VStack(spacing: PlanMetrics.sectionGap) {
                Image(systemName: "moon").frame(width: PlanMetrics.touch, height: PlanMetrics.touch)
                    .foregroundStyle(ColorToken.dawnForeground.color).background(ColorToken.dawn.color, in: Circle())
                Text(verbatim: copy("End of this plan")).font(Typography.planCardTitle.font).accessibilityAddTraits(
                    .isHeader)
                Text(verbatim: plan.endText).font(Typography.authBody.font).foregroundStyle(
                    ColorToken.mutedForeground.color)
                if let assumed = plan.assumedEnd { Text(verbatim: assumed).font(Typography.planSubtitle.font) }
                if let day = plan.returnDayID {
                    Button(copy("See your return plan")) { select(day) }.buttonStyle(.borderedProminent)
                }
            }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("trip.plan.end")
    }
}

struct DayNavigation: View {
    let days: [PreparedDay]
    let selected: String?
    let copy: PageCopy
    let select: (String) -> Void
    var body: some View {
        HStack(spacing: PlanMetrics.smallGap) {
            step(-1, label: "Previous day", icon: "chevron.left")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: PlanMetrics.rowGap) {
                        ForEach(days) { day in
                            Button {
                                select(day.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: day.title).font(Typography.authStrong.font)
                                    Text(verbatim: day.date).font(Typography.planSubtitle.font)
                                }.padding(.horizontal, PlanMetrics.gutter).frame(minHeight: PlanMetrics.touch)
                            }.buttonStyle(.plain)
                                .foregroundStyle(
                                    day.id == selected ? ColorToken.dawnForeground.color : ColorToken.foreground.color
                                )
                                .background(
                                    day.id == selected ? ColorToken.dawn.color : ColorToken.card.color, in: Capsule()
                                )
                                .overlay(Capsule().strokeBorder(ColorToken.border.color, lineWidth: PlanMetrics.border))
                                .accessibilityLabel(Text(verbatim: day.title + ", " + day.date))
                                .accessibilityAddTraits(day.id == selected ? .isSelected : [])
                                .id(day.id)
                        }
                    }
                }.accessibilityLabel(copy("Plan days"))
                    .onChange(of: selected) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
            step(1, label: "Next day", icon: "chevron.right")
        }
    }
    private func step(_ delta: Int, label: String, icon: String) -> some View {
        let index = (days.firstIndex { $0.id == selected } ?? 0) + delta
        return Button(copy(label), systemImage: icon) { if days.indices.contains(index) { select(days[index].id) } }
            .labelStyle(.iconOnly).frame(minWidth: PlanMetrics.touch, minHeight: PlanMetrics.touch).disabled(
                !days.indices.contains(index))
    }
}

struct PriorityKey: View {
    let copy: PageCopy
    var body: some View {
        VStack(alignment: .leading, spacing: PlanMetrics.rowGap) {
            Text(verbatim: copy("Priorities")).font(Typography.planTitle.font)
            ForEach(
                Array(
                    zip(
                        ["Important", "Recommended", "Optional", "Information"],
                        [
                            "The steps that matter most for shifting your clock.", "Helpful when they fit your day.",
                            "Extra support if you want it.", "Useful context, not a task.",
                        ])), id: \.0
            ) { title, description in
                HStack {
                    RoundedRectangle(cornerRadius: PlanMetrics.tileRadius).strokeBorder(
                        ColorToken.foreground.color,
                        style: StrokeStyle(
                            lineWidth: title == "Important" ? PlanMetrics.coreBorder : PlanMetrics.border,
                            dash: title == "Optional" ? [PlanMetrics.smallGap] : [])
                    )
                    .frame(width: PlanMetrics.prioritySampleWidth, height: PlanMetrics.prioritySampleHeight)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(verbatim: copy(title)).font(Typography.authStrong.font)
                        Text(verbatim: copy(description)).font(Typography.planSubtitle.font)
                    }
                }.accessibilityElement(children: .combine)
            }
        }
    }
}

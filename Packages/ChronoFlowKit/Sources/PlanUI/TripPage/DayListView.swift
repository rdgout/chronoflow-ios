import AppCore
import DesignSystem
import PlanCore
import SwiftUI

public struct DayListView: View {
    public let day: PreparedDay
    public var onBlock: (String) -> Void
    public init(day: PreparedDay, onBlock: @escaping (String) -> Void = { _ in }) {
        self.day = day
        self.onBlock = onBlock
    }

    public var body: some View {
        LazyVStack(spacing: PlanMetrics.rowGap) {
            ForEach(day.blocks) { block in
                if block.block.type == .zoneChange {
                    ZoneChangeCard(block: block, onBlock: onBlock)
                } else {
                    Button {
                        onBlock(block.id)
                    } label: {
                        row(block)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text(verbatim: block.accessibilityLabel))
                    .accessibilityIdentifier("trip.block.\(block.id)")
                }
            }
        }
    }

    private func row(_ block: PreparedBlock) -> some View {
        let style = PlanCategoryStyle(block.block.type)
        return HStack(alignment: .top, spacing: PlanMetrics.rowGap) {
            Image(systemName: style.icon).frame(width: PlanMetrics.touch).padding(.top, PlanMetrics.smallGap)
            VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                Text(verbatim: block.title).font(Typography.authStrong.font)
                Text(verbatim: block.interval).font(Typography.planListLine.font).monospacedDigit()
                PriorityTag(label: block.priority)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let status = block.status {
                Image(systemName: status == .done ? "checkmark.circle.fill" : "minus.circle")
            }
            Image(systemName: "chevron.right").font(Typography.authMeta.font)
        }
        .padding(PlanMetrics.sectionGap)
        .foregroundStyle(style.foreground.color)
        .background(style.fill.color)
        .overlay {
            if let pattern = style.pattern {
                if pattern == .dots {
                    PlanPattern(dots: true).fill(style.foreground.color.opacity(PlanMetrics.dotOpacity))
                } else {
                    PlanPattern(dots: false).stroke(
                        style.foreground.color.opacity(PlanMetrics.hatchOpacity), lineWidth: PlanMetrics.patternLine)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PlanMetrics.rowRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).strokeBorder(
                block.block.type == .noCaffeine
                    ? ColorToken.catCaffeine.color : style.foreground.color.opacity(PlanMetrics.tagOpacity),
                style: StrokeStyle(lineWidth: PlanMetrics.border, dash: style.dashed ? [PlanMetrics.smallGap] : []))
        )
        .overlay(alignment: .leading) {
            if block.block.priority == .core {
                Capsule().fill(style.foreground.color).frame(width: PlanMetrics.coreBorder).padding(
                    .vertical, PlanMetrics.sectionGap)
            }
        }
    }
}

struct ZoneChangeCard: View {
    let block: PreparedBlock
    let onBlock: (String) -> Void
    var body: some View {
        Button {
            onBlock(block.id)
        } label: {
            HStack(alignment: .top, spacing: PlanMetrics.sectionGap) {
                Image(systemName: "mappin").frame(width: PlanMetrics.touch, height: PlanMetrics.touch)
                    .foregroundStyle(ColorToken.dawnForeground.color).background(ColorToken.dawn.color, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PlanMetrics.rowGap) {
                    Text(verbatim: block.title).font(Typography.planCardTitle.font)
                    if let text = block.zoneInstruction { plate(text, font: Typography.authHint.font) }
                    if let comparison = block.zoneComparison {
                        plate(comparison, font: Typography.planSubtitle.font).monospacedDigit()
                    }
                }
            }.padding(PlanMetrics.zonePadding).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(ColorToken.skyTitle.color).background { CfSky() }
                .clipShape(RoundedRectangle(cornerRadius: PlanMetrics.cardRadius))
        }.buttonStyle(.plain).accessibilityLabel(
            Text(
                verbatim: [block.title, block.zoneInstruction, block.zoneComparison].compactMap { $0 }.joined(
                    separator: ". ")))
    }
    private func plate(_ text: String, font: Font) -> some View {
        Text(verbatim: text).font(font).foregroundStyle(ColorToken.skyCopy.color)
            .padding(.horizontal, PlanMetrics.rowGap).padding(.vertical, PlanMetrics.smallGap)
            .background(
                ColorToken.skyCopyBackground.color, in: RoundedRectangle(cornerRadius: PlanMetrics.textPlateRadius))
    }

}

import AppCore
import DesignSystem
import PlanCore
import SwiftUI

public struct DayListView: View {
    public let day: PreparedDay
    public var now: Date
    public var copy: PageCopy
    public var onBlock: (String) -> Void
    public var selectedBlockID: String?
    public init(
        day: PreparedDay, now: Date = .distantPast, copy: PageCopy = PageCopy(language: .en),
        selectedBlockID: String? = nil, onBlock: @escaping (String) -> Void = { _ in }
    ) {
        self.day = day
        self.now = now
        self.copy = copy
        self.onBlock = onBlock
        self.selectedBlockID = selectedBlockID
    }

    public var body: some View {
        LazyVStack(spacing: PlanMetrics.rowGap) {
            ForEach(day.blocks) { block in
                if block.block.type == .zoneChange {
                    ZoneChangeCard(block: block, onBlock: onBlock)
                        .overlay {
                            if selectedBlockID == block.id {
                                RoundedRectangle(cornerRadius: PlanMetrics.cardRadius).strokeBorder(
                                    ColorToken.dawn.color, lineWidth: PlanMetrics.emphasisBorder)
                            }
                        }
                } else {
                    Button {
                        onBlock(block.id)
                    } label: {
                        row(block)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text(verbatim: rowLabel(block)))
                    .accessibilityIdentifier("trip.block.\(block.id)")
                }
            }
        }
    }

    private func interval(_ block: PreparedBlock) -> String {
        planDate(block.block.startUtc) <= now && now < planDate(block.block.endUtc)
            ? copy("%@ · now", block.interval) : block.interval
    }

    private func rowLabel(_ block: PreparedBlock) -> String {
        [
            block.title, interval(block),
            block.block.priority == .core || block.block.priority == .optional ? block.priority : nil,
            block.status.map { copy($0 == .done ? "Marked done" : "Skipped") },
        ]
        .compactMap { $0 }.joined(separator: ", ")
    }

    private func row(_ block: PreparedBlock) -> some View {
        HStack(alignment: .center, spacing: PlanMetrics.sectionGap) {
            TripPageCategorySwatch(type: block.block.type)
            VStack(alignment: .leading, spacing: PlanMetrics.smallGap) {
                Text(verbatim: block.title).font(Typography.authStrong.font)
                Text(verbatim: interval(block)).font(Typography.planListLine.font).monospacedDigit()
                    .foregroundStyle(ColorToken.mutedForeground.color)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PlanMetrics.rowGap) { trailing(block) }
                VStack(alignment: .trailing, spacing: PlanMetrics.rowGap) { trailing(block) }
            }
        }
        .padding(.horizontal, PlanMetrics.blockIcon).padding(.vertical, PlanMetrics.sectionGap)
        .foregroundStyle(ColorToken.cardForeground.color)
        .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanMetrics.rowRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PlanMetrics.rowRadius).strokeBorder(
                selectedBlockID == block.id ? ColorToken.dawn.color : ColorToken.border.color,
                style: StrokeStyle(
                    lineWidth: selectedBlockID == block.id ? PlanMetrics.emphasisBorder : PlanMetrics.border,
                    dash: block.block.priority == .optional && selectedBlockID != block.id
                        ? [PlanMetrics.smallGap, PlanMetrics.smallGap] : []))
        )
        .opacity(block.status == nil ? 1 : PlanMetrics.markedRowOpacity)
    }

    @ViewBuilder private func trailing(_ block: PreparedBlock) -> some View {
        if block.block.priority == .core || block.block.priority == .optional {
            TripPagePriorityTag(label: block.priority)
        }
        if let status = block.status {
            Image(systemName: status == .done ? "checkmark" : "forward.end")
                .foregroundStyle(ColorToken.dawnText.color).accessibilityHidden(true)
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

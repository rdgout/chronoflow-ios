import AppCore
import DesignSystem
import PlanCore
import SwiftUI

public struct DayTimelineView: View {
    public let day: PreparedDay
    public let layout: DayLayout
    public let now: Date
    public let nowText: String
    public let copy: PageCopy
    public let renderer: TimelineRenderer
    public var onBlock: (String) -> Void = { _ in }
    public var onFrame: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption2) private var fontSize = Typography.planLane.size
    @State private var image: Image?
    private let symbols: TimelineSymbols
    @State private var renderFailed = false

    public init(
        day: PreparedDay, layout: DayLayout, now: Date, nowText: String, copy: PageCopy,
        renderer: TimelineRenderer, symbols: TimelineSymbols = TimelineSymbols(),
        onBlock: @escaping (String) -> Void = { _ in }, onFrame: @escaping () -> Void = {}
    ) {
        self.day = day
        self.layout = layout
        self.now = now
        self.nowText = nowText
        self.copy = copy
        self.symbols = symbols
        self.renderer = renderer
        self.onBlock = onBlock
        self.onFrame = onFrame
    }
    public var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(layout: layout, availableWidth: proxy.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                drawing(geometry).frame(width: geometry.width, height: geometry.height)
            }
            .task(
                id: RenderKey(
                    width: proxy.size.width, scale: displayScale, size: fontSize, dark: colorScheme == .dark, day: day,
                    layout: layout)
            ) {
                do {
                    let appearance: TokenAppearance = colorScheme == .dark ? .dark : .light
                    let glyphs = symbols.images(appearance: appearance, scale: displayScale)
                    let bitmap = try await renderer.render(
                        day: day, layout: layout, width: proxy.size.width,
                        scale: displayScale, fontSize: fontSize, appearance: appearance, symbols: glyphs)
                    guard !Task.isCancelled else { return }
                    image = Image(decorative: bitmap, scale: displayScale)
                    renderFailed = false
                } catch { renderFailed = true }
            }
            .onDisappear { image = nil }
        }.frame(height: layout.height)
    }

    private func drawing(_ geometry: TimelineGeometry) -> some View {
        let offset = nowLineOffset(layout.day, now: now)
        let nowLabel = Text(verbatim: nowText).font(Typography.planCompactDate.font).foregroundColor(
            ColorToken.primaryForeground.color)
        let line = offset.map { y in
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: geometry.width, y: y))
            }
        }
        return Canvas { context, size in
            if let image { context.draw(image, in: CGRect(origin: .zero, size: size)) }
            if let line, let offset {
                context.stroke(line, with: .color(ColorToken.now.color), lineWidth: PlanMetrics.emphasisBorder)
                let rect = CGRect(
                    x: 0, y: offset - PlanMetrics.icon / 2, width: PlanMetrics.gutterWidth, height: PlanMetrics.icon)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: PlanMetrics.tileRadius), with: .color(ColorToken.now.color))
                context.draw(nowLabel, at: CGPoint(x: PlanMetrics.gutterWidth / 2, y: offset))
            }
        }
        .overlay {
            if renderFailed {
                DayListView(day: day, onBlock: onBlock)
            } else if image == nil {
                ColorToken.surface2.color.accessibilityHidden(true)
            }
        }
        .onChange(of: image != nil) { _, ready in if ready { onFrame() } }
        .onTapGesture { point in
            let candidates = geometry.tiles.filter { $0.hitFrame.contains(point) }
            if let tile = candidates.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }) {
                onBlock(tile.blockID)
            } else if let marker = layout.markers.first(where: {
                abs($0.top - point.y) <= PlanMetrics.touch / 2 && point.x <= PlanMetrics.gutterWidth
            }) {
                onBlock(marker.block.id)
            } else if let zone = layout.changes.first(where: { abs($0.top - point.y) <= PlanMetrics.touch / 2 }) {
                onBlock(zone.block.id)
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel(copy("Plan timeline"))
        .accessibilityIdentifier(image == nil ? "trip.timeline.preparing" : "trip.timeline.ready")
        .accessibilityChildren {
            ForEach(day.blocks) { block in
                Button {
                    onBlock(block.id)
                } label: {
                    Text(verbatim: block.accessibilityLabel)
                }
                .accessibilityIdentifier("trip.block.\(block.id)")
            }
            if offset != nil { Text(verbatim: copy("Now, %@", nowText)) }
        }
    }
}

private struct RenderKey: Equatable {
    var width: Double
    var scale: Double
    var size: Double
    var dark: Bool
    var day: PreparedDay
    var layout: DayLayout
}

struct LaneHeadings: View {
    let copy: PageCopy
    var body: some View {
        HStack(spacing: PlanMetrics.laneGap) {
            Color.clear.frame(width: PlanMetrics.gutterWidth).accessibilityHidden(true)
            ForEach(
                Array(
                    zip(
                        ["Sleep", "Light", "Caffeine", "Travel"],
                        [ColorToken.catSleep, .catLight, .catCaffeine, .catTravel])), id: \.0
            ) { label, color in
                HStack(spacing: PlanMetrics.smallGap) {
                    Circle().fill(color.color).frame(width: PlanMetrics.dot, height: PlanMetrics.dot)
                    Text(verbatim: copy(label)).font(Typography.planLane.font).lineLimit(1)
                }.frame(maxWidth: .infinity)
            }
        }.foregroundStyle(ColorToken.mutedForeground.color).accessibilityHidden(true)
    }
}

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
    public var viewportHeight: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .caption2) private var fontSize = Typography.planLane.size
    @ScaledMetric(relativeTo: .caption2) private var nowHeight = PlanMetrics.planNowLineHeight
    @State private var drawing: TimelineDrawing?
    private let symbols: TimelineSymbols
    @State private var renderFailed = false

    public init(
        day: PreparedDay, layout: DayLayout, now: Date, nowText: String, copy: PageCopy,
        renderer: TimelineRenderer, symbols: TimelineSymbols = TimelineSymbols(), viewportHeight: Double = 0,
        onBlock: @escaping (String) -> Void = { _ in }, onFrame: @escaping () -> Void = {}
    ) {
        self.day = day
        self.layout = layout
        self.now = now
        self.nowText = nowText
        self.copy = copy
        self.symbols = symbols
        self.renderer = renderer
        self.viewportHeight = viewportHeight
        self.onBlock = onBlock
        self.onFrame = onFrame
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = TimelineGeometry(layout: layout, availableWidth: proxy.size.width)
            Group {
                if geometry.width > proxy.size.width {
                    ScrollView(.horizontal, showsIndicators: false) { content(geometry) }
                } else {
                    content(geometry)
                }
            }
            .task(
                id: RenderKey(
                    width: proxy.size.width, scale: displayScale, size: fontSize, dark: colorScheme == .dark,
                    day: day, layout: layout)
            ) {
                do {
                    let appearance: TokenAppearance = colorScheme == .dark ? .dark : .light
                    let glyphs = symbols.images(appearance: appearance, scale: displayScale)
                    let value = try await renderer.render(
                        day: day, layout: layout, width: proxy.size.width, scale: displayScale,
                        fontSize: fontSize, appearance: appearance, symbols: glyphs)
                    guard !Task.isCancelled else { return }
                    drawing = value
                    renderFailed = false
                    onFrame()
                } catch is CancellationError {
                } catch { renderFailed = true }
            }
            .onDisappear { drawing = nil }
        }.frame(height: layout.height)
    }

    private func content(_ geometry: TimelineGeometry) -> some View {
        let sliceHeight = max(PlanMetrics.touch, viewportHeight / 2)
        return ZStack(alignment: .topLeading) {
            if let drawing {
                StaticTimelineDrawing(
                    drawing: drawing, width: geometry.width, height: geometry.height, sliceHeight: sliceHeight
                ).equatable()
            } else {
                ColorToken.surface2.color.accessibilityHidden(true)
            }
            if renderFailed { DayListView(day: day, now: now, copy: copy, onBlock: onBlock) }
            if let offset = nowLineOffset(layout.day, now: now) {
                Text(verbatim: nowText).font(Typography.planNow.font).monospacedDigit()
                    .foregroundStyle(ColorToken.primaryForeground.color)
                    .padding(.horizontal, PlanMetrics.tilePadding).frame(minHeight: nowHeight)
                    .background(ColorToken.now.color, in: Capsule()).fixedSize()
                    .frame(width: geometry.width, alignment: .leading)
                    .background(alignment: .center) {
                        ColorToken.now.color.frame(height: PlanMetrics.emphasisBorder)
                    }
                    .offset(y: offset - nowHeight / 2)
                    .accessibilityElement(children: .ignore).accessibilityLabel(copy("Now, %@", nowText))
            }
        }
        .frame(width: geometry.width, height: geometry.height, alignment: .topLeading)
        .contentShape(Rectangle())
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
        .accessibilityIdentifier(drawing == nil ? "trip.timeline.preparing" : "trip.timeline.ready")
        .accessibilityChildren {
            ZStack(alignment: .topLeading) {
                ForEach(day.blocks) { block in
                    if let frame = timelineBlockFrame(block.id, geometry: geometry, layout: layout) {
                        Button {
                            onBlock(block.id)
                        } label: {
                            Text(verbatim: block.accessibilityLabel)
                        }
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityIdentifier("trip.block.\(block.id)")
                    }
                }
                ForEach(Array(layout.dividers.enumerated()), id: \.offset) { index, divider in
                    let frame =
                        drawing?.dividerFrames[index]
                        ?? CGRect(
                            x: PlanMetrics.gutterWidth + PlanMetrics.laneGap, y: divider.top - PlanMetrics.touch / 2,
                            width: geometry.width - PlanMetrics.gutterWidth - PlanMetrics.laneGap,
                            height: PlanMetrics.touch)
                    Text(verbatim: day.dividerLabels[index]).frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
                ForEach(Array(layout.ticks.enumerated()), id: \.offset) { index, tick in
                    if tick.visible {
                        Text(verbatim: day.ticks[index])
                            .frame(
                                width: PlanMetrics.gutterWidth,
                                height: fontSize * PlanMetrics.laneLabelLineHeight / PlanMetrics.laneLabelSize
                            )
                            .position(x: PlanMetrics.gutterWidth / 2, y: tick.top)
                    }
                }
            }.frame(width: geometry.width, height: geometry.height)
        }
    }
}

private struct StaticTimelineDrawing: View, Equatable {
    let drawing: TimelineDrawing
    let width: Double
    let height: Double
    let sliceHeight: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.drawing.document === rhs.drawing.document && lhs.width == rhs.width
            && lhs.height == rhs.height && lhs.sliceHeight == rhs.sliceHeight
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<Int(ceil(height / sliceHeight)), id: \.self) { index in
                let top = Double(index) * sliceHeight
                Canvas(opaque: true) { context, _ in
                    context.withCGContext { context in
                        context.translateBy(x: 0, y: height - top)
                        context.scaleBy(x: 1, y: -1)
                        context.drawPDFPage(drawing.page)
                    }
                }.frame(width: width, height: min(sliceHeight, height - top))
            }
        }.accessibilityHidden(true)
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
    var day: PreparedDay?
    var body: some View {
        HStack(spacing: PlanMetrics.laneGap) {
            Group {
                if let day {
                    VStack(spacing: 0) {
                        Text(verbatim: day.weekday).font(Typography.planPriority.font)
                        Text(verbatim: day.dayMonth).font(Typography.planCompactDate.font).monospacedDigit()
                    }
                } else {
                    Color.clear
                }
            }.frame(width: PlanMetrics.gutterWidth).accessibilityHidden(true)
            ForEach(
                Array(
                    zip(
                        ["Sleep", "Light", "Caffeine", "Travel"],
                        [ColorToken.catSleep, .catLight, .catCaffeine, .catTravel])), id: \.0
            ) { label, color in
                HStack(spacing: PlanMetrics.smallGap) {
                    Circle().fill(color.color).frame(width: PlanMetrics.dot, height: PlanMetrics.dot)
                    Text(verbatim: copy(label)).font(Typography.planLane.font).lineLimit(1)
                }.frame(maxWidth: .infinity).accessibilityHidden(true)
            }
        }.foregroundStyle(ColorToken.mutedForeground.color)
            .accessibilityElement(children: .ignore).accessibilityLabel(day.map { $0.title + ", " + $0.date } ?? "")
            .accessibilityHidden(day == nil)
    }
}

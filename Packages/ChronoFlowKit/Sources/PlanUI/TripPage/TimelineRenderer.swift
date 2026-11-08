import AppCore
import CoreGraphics
import CoreText
import DesignSystem
import Foundation
import PlanCore
import SwiftUI

public actor TimelineRenderer {
    private struct Entry {
        var day: PreparedDay
        var layout: DayLayout
        var width: Double
        var scale: Double
        var fontSize: Double
        var appearance: TokenAppearance
        var image: CGImage
    }
    private var cache: [String: Entry] = [:]
    private var order: [String] = []
    public private(set) var renderCount = 0
    public init() {}

    public func render(
        day: PreparedDay, layout: DayLayout, width: Double, scale: Double, fontSize: Double,
        appearance: TokenAppearance, symbols: [String: CGImage]
    ) throws -> CGImage {
        let key = day.id
        if let c = cache[key], c.day == day, c.layout == layout, c.width == width, c.scale == scale,
            c.fontSize == fontSize, c.appearance == appearance
        {
            touch(key)
            return c.image
        }
        let image = try rasterTimeline(
            day: day, layout: layout, width: width, scale: scale,
            fontSize: fontSize, appearance: appearance, symbols: symbols)
        cache[key] = Entry(
            day: day, layout: layout, width: width, scale: scale, fontSize: fontSize, appearance: appearance,
            image: image)
        renderCount += 1
        touch(key)
        while order.count > 4 { cache[order.removeFirst()] = nil }
        return image
    }
    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

@MainActor final class TimelineSymbols {
    private var cache: [String: [String: CGImage]] = [:]
    func images(appearance: TokenAppearance, scale: Double) -> [String: CGImage] {
        let key = "\(appearance.rawValue)-\(scale)"
        if let cached = cache[key] { return cached }
        var images: [String: CGImage] = [:]
        for type in [
            BlockType.sleep, .nap, .rest, .seekLight, .avoidLight, .lightOK, .lightNeutral,
            .caffeineServing, .noCaffeine, .flight, .layover, .transfer, .movementBreak, .zoneChange, .note,
        ] {
            let style = PlanCategoryStyle(type)
            let renderer = ImageRenderer(
                content: Image(systemName: style.icon)
                    .font(.system(size: PlanMetrics.icon)).foregroundStyle(
                        style.foreground.components(for: appearance).color
                    )
                    .frame(width: PlanMetrics.icon, height: PlanMetrics.icon))
            renderer.scale = scale
            images[type.rawValue] = renderer.cgImage
        }
        images[BlockType.caffeineRoutine.rawValue] = images[BlockType.caffeineServing.rawValue]
        images[BlockType.caffeineOK.rawValue] = images[BlockType.caffeineServing.rawValue]
        cache[key] = images
        return images
    }
}

private enum TimelineRenderFailure: Error { case context, image }

nonisolated private func rasterTimeline(
    day: PreparedDay, layout: DayLayout, width: Double, scale: Double,
    fontSize: Double, appearance: TokenAppearance, symbols: [String: CGImage]
) throws -> CGImage {
    let geometry = TimelineGeometry(layout: layout, availableWidth: width)
    guard
        let context = CGContext(
            data: nil, width: Int(ceil(geometry.width * scale)), height: Int(ceil(layout.height * scale)),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw TimelineRenderFailure.context }
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: layout.height)
    context.scaleBy(x: 1, y: -1)
    func color(_ token: ColorToken) -> CGColor { token.components(for: appearance).cgColor }
    let bounds = CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height)
    context.setFillColor(color(.background))
    context.fill(bounds)
    let font = CTFontCreateWithName(FontFace.figtree500.rawValue as CFString, fontSize, nil)
    let titleFont = CTFontCreateWithName(FontFace.figtree600.rawValue as CFString, fontSize, nil)
    func text(_ value: String, rect: CGRect, color: CGColor, font: CTFont, wrap: Bool = false) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.clip(to: rect)
        let attributed = NSAttributedString(
            string: value,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let lineHeight = fontSize / 11 * 14
        var start = 0
        var y = rect.minY
        while start < attributed.length && y + lineHeight <= rect.maxY {
            let count = wrap ? max(1, CTTypesetterSuggestLineBreak(typesetter, start, rect.width)) : attributed.length
            var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            if !wrap, CTLineGetTypographicBounds(line, nil, nil, nil) > rect.width {
                let token = CTLineCreateWithAttributedString(
                    NSAttributedString(string: "…", attributes: attributed.attributes(at: 0, effectiveRange: nil)))
                line = CTLineCreateTruncatedLine(line, rect.width, .end, token) ?? line
            }
            context.saveGState()
            context.translateBy(x: rect.minX, y: y + fontSize)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
            if !wrap { break }
            start += count
            y += lineHeight
        }
        context.restoreGState()
    }
    func line(
        _ x: Double, _ y: Double, _ endX: Double, _ endY: Double, token: ColorToken, dashed: Bool = false,
        thickness: Double = PlanMetrics.line
    ) {
        context.setStrokeColor(color(token))
        context.setLineWidth(thickness)
        context.setLineDash(phase: 0, lengths: dashed ? [PlanMetrics.smallGap, PlanMetrics.smallGap] : [])
        context.move(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: endX, y: endY))
        context.strokePath()
    }
    for index in timelineLanes.indices {
        let x =
            PlanMetrics.gutterWidth + PlanMetrics.laneGap + Double(index) * (geometry.laneWidth + PlanMetrics.laneGap)
        context.setFillColor(color(.surface2))
        context.fill(CGRect(x: x, y: 0, width: geometry.laneWidth, height: layout.height))
    }
    for (index, tick) in layout.ticks.enumerated() {
        line(PlanMetrics.gutterWidth, tick.top, geometry.width, tick.top, token: .border)
        if tick.visible {
            text(
                day.ticks[index],
                rect: CGRect(
                    x: 0, y: tick.top + PlanMetrics.smallGap, width: PlanMetrics.gutterWidth - PlanMetrics.smallGap,
                    height: fontSize * 2), color: color(.mutedForeground), font: font)
        }
    }
    let blocks = Dictionary(uniqueKeysWithValues: day.blocks.map { ($0.id, $0) })
    for tile in geometry.tiles {
        guard let block = blocks[tile.blockID] else { continue }
        let style = PlanCategoryStyle(block.block.type)
        let rect = tile.frame
        let path = CGPath(
            roundedRect: rect, cornerWidth: PlanMetrics.tileRadius, cornerHeight: PlanMetrics.tileRadius, transform: nil
        )
        context.saveGState()
        context.addPath(path)
        context.setFillColor(color(style.fill))
        context.fillPath()
        context.addPath(path)
        context.clip()
        if let pattern = style.pattern {
            context.setAlpha(0.12)
            context.setFillColor(color(style.foreground))
            context.setStrokeColor(color(style.foreground))
            if pattern == .dots {
                for y in stride(from: rect.minY + PlanMetrics.dotStep / 2, to: rect.maxY, by: PlanMetrics.dotStep) {
                    for x in stride(from: rect.minX + PlanMetrics.dotStep / 2, to: rect.maxX, by: PlanMetrics.dotStep) {
                        context.fillEllipse(
                            in: CGRect(x: x, y: y, width: PlanMetrics.dotRadius * 2, height: PlanMetrics.dotRadius * 2))
                    }
                }
            } else {
                context.setLineWidth(PlanMetrics.patternLine)
                for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: PlanMetrics.patternStep) {
                    context.move(to: CGPoint(x: x, y: rect.maxY))
                    context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                }
                context.strokePath()
            }
            context.setAlpha(1)
        }
        if block.block.priority == .core {
            line(
                rect.minX, rect.minY, rect.minX, rect.maxY, token: style.foreground,
                thickness: PlanMetrics.coreBorder * 2)
        }
        context.setStrokeColor(color(block.block.type == .noCaffeine ? .catCaffeine : style.foreground))
        context.setLineWidth(PlanMetrics.border)
        context.setLineDash(phase: 0, lengths: style.dashed ? [PlanMetrics.smallGap, PlanMetrics.smallGap] : [])
        context.addPath(path)
        context.strokePath()
        let icon = symbols[block.block.type.rawValue]
        let iconOnly = tile.tiny || rect.width < PlanMetrics.touch
        let inset = PlanMetrics.tilePadding
        let iconRect = CGRect(
            x: iconOnly ? rect.midX - PlanMetrics.icon / 2 : rect.minX + inset,
            y: iconOnly
                ? rect.midY - PlanMetrics.icon / 2 : rect.minY + inset + (tile.continuesBefore ? PlanMetrics.icon : 0),
            width: PlanMetrics.icon, height: PlanMetrics.icon)
        if let icon {
            context.saveGState()
            context.translateBy(x: iconRect.minX, y: iconRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(icon, in: CGRect(origin: .zero, size: iconRect.size))
            context.restoreGState()
        }
        if !iconOnly {
            let top = iconRect.maxY + PlanMetrics.smallGap
            let remaining = rect.height - (top - rect.minY) - inset - (tile.continuesAfter ? PlanMetrics.icon : 0)
            text(
                block.title,
                rect: CGRect(
                    x: rect.minX + inset, y: top, width: rect.width - inset * 2, height: max(0, remaining / 2)),
                color: color(style.foreground), font: titleFont, wrap: true)
            text(
                block.interval,
                rect: CGRect(
                    x: rect.minX + inset, y: top + max(0, remaining / 2), width: rect.width - inset * 2,
                    height: max(0, remaining / 2)), color: color(style.foreground), font: font, wrap: true)
        }
        if let status = block.status {
            text(
                status == .done ? "✓" : "−",
                rect: CGRect(
                    x: rect.maxX - PlanMetrics.icon, y: rect.minY, width: PlanMetrics.icon, height: PlanMetrics.icon * 2
                ), color: color(style.foreground), font: titleFont)
        }
        for (show, y, up) in [
            (tile.continuesBefore, rect.minY + PlanMetrics.smallGap, true),
            (tile.continuesAfter, rect.maxY - PlanMetrics.smallGap * 2, false),
        ] where show {
            let x = rect.midX
            line(
                x - PlanMetrics.smallGap, y + (up ? PlanMetrics.smallGap : 0), x, y + (up ? 0 : PlanMetrics.smallGap),
                token: style.foreground)
            line(
                x, y + (up ? 0 : PlanMetrics.smallGap), x + PlanMetrics.smallGap, y + (up ? PlanMetrics.smallGap : 0),
                token: style.foreground)
        }
        context.restoreGState()
    }
    for divider in layout.dividers {
        line(
            PlanMetrics.gutterWidth, divider.top, geometry.width, divider.top, token: .catTravel, dashed: true,
            thickness: PlanMetrics.emphasisBorder)
    }
    for change in layout.changes {
        guard let block = blocks[change.block.id] else { continue }
        let rect = CGRect(
            x: PlanMetrics.gutterWidth + PlanMetrics.smallGap, y: change.top,
            width: geometry.width - PlanMetrics.gutterWidth - PlanMetrics.smallGap, height: fontSize * 2)
        context.setFillColor(color(.catTravel))
        context.fill(rect)
        text(
            block.title, rect: rect.insetBy(dx: PlanMetrics.smallGap, dy: 0), color: color(.catTravelFg),
            font: titleFont)
    }
    for marker in layout.markers {
        let rect = CGRect(
            x: PlanMetrics.gutterWidth - PlanMetrics.gutterMarkerSize, y: marker.top - PlanMetrics.gutterMarkerSize / 2,
            width: PlanMetrics.gutterMarkerSize, height: PlanMetrics.gutterMarkerSize)
        context.setFillColor(color(.card))
        context.fillEllipse(in: rect)
        text("i", rect: rect.insetBy(dx: PlanMetrics.smallGap, dy: 0), color: color(.foreground), font: titleFont)
    }
    guard let image = context.makeImage() else { throw TimelineRenderFailure.image }
    return image
}

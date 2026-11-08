import AppCore
import CoreGraphics
import CoreText
import DesignSystem
import Foundation
import PlanCore
import SwiftUI

// Prepared once on the renderer actor; Canvas consumers only read the immutable document.
nonisolated public struct TimelineDrawing: @unchecked Sendable {
    public let document: CGPDFDocument
    public let byteCount: Int
    public let dividerFrames: [CGRect]
    public var page: CGPDFPage { document.page(at: 1)! }
}

public actor TimelineRenderer {
    public static let cacheByteLimit = 4 * 1_024 * 1_024
    public private(set) var cachedBytes = 0
    private struct Entry {
        var day: PreparedDay
        var layout: DayLayout
        var width: Double
        var scale: Double
        var fontSize: Double
        var appearance: TokenAppearance
        var drawing: TimelineDrawing
    }
    private var cache: [String: Entry] = [:]
    private var order: [String] = []
    public private(set) var renderCount = 0
    public init() {}

    public func render(
        day: PreparedDay, layout: DayLayout, width: Double, scale: Double, fontSize: Double,
        appearance: TokenAppearance, symbols: [String: CGImage]
    ) throws -> TimelineDrawing {
        try Task.checkCancellation()
        let key = day.id
        if let c = cache[key], c.day == day, c.layout == layout, c.width == width, c.scale == scale,
            c.fontSize == fontSize, c.appearance == appearance
        {
            touch(key)
            return c.drawing
        }
        let drawing = try vectorTimeline(
            day: day, layout: layout, width: width, scale: scale,
            fontSize: fontSize, appearance: appearance, symbols: symbols)
        try Task.checkCancellation()
        if let previous = cache[key] { cachedBytes -= previous.drawing.byteCount }
        cache[key] = Entry(
            day: day, layout: layout, width: width, scale: scale, fontSize: fontSize, appearance: appearance,
            drawing: drawing)
        cachedBytes += drawing.byteCount
        renderCount += 1
        touch(key)
        while cachedBytes > Self.cacheByteLimit || order.count > 4 {
            if let evicted = cache.removeValue(forKey: order.removeFirst()) { cachedBytes -= evicted.drawing.byteCount }
        }
        return drawing
    }
    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

@MainActor public final class TimelineSymbols {
    public init() {}
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
        for (key, name) in [("status.done", "checkmark"), ("status.skipped", "forward.end")] {
            let renderer = ImageRenderer(
                content: Image(systemName: name).font(.system(size: PlanMetrics.blockIcon))
                    .foregroundStyle(ColorToken.foreground.components(for: appearance).color)
                    .frame(width: PlanMetrics.blockIcon, height: PlanMetrics.blockIcon))
            renderer.scale = scale
            images[key] = renderer.cgImage
        }
        images[BlockType.caffeineRoutine.rawValue] = images[BlockType.caffeineServing.rawValue]
        images[BlockType.caffeineOK.rawValue] = images[BlockType.caffeineServing.rawValue]
        cache[key] = images
        return images
    }
}

private enum TimelineRenderFailure: Error { case context, document }

nonisolated private func vectorTimeline(
    day: PreparedDay, layout: DayLayout, width: Double, scale: Double,
    fontSize: Double, appearance: TokenAppearance, symbols: [String: CGImage]
) throws -> TimelineDrawing {
    let geometry = TimelineGeometry(layout: layout, availableWidth: width)
    let data = NSMutableData()
    var bounds = CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height)
    guard let consumer = CGDataConsumer(data: data),
        let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)
    else { throw TimelineRenderFailure.context }
    context.beginPDFPage(nil)
    context.translateBy(x: 0, y: layout.height)
    context.scaleBy(x: 1, y: -1)
    func color(_ token: ColorToken) -> CGColor { token.components(for: appearance).cgColor }
    context.setFillColor(color(.background))
    context.fill(bounds)
    let font = CTFontCreateWithName(FontFace.figtree400.rawValue as CFString, fontSize, nil)
    let tagSize = fontSize * PlanMetrics.planPrioritySize / PlanMetrics.laneLabelSize
    let tagFont = CTFontCreateWithName(FontFace.figtree500.rawValue as CFString, tagSize, nil)
    let lineHeight = fontSize / PlanMetrics.laneLabelSize * PlanMetrics.laneLabelLineHeight
    let tagHeight = fontSize / PlanMetrics.laneLabelSize * PlanMetrics.planPriorityLineHeight
    func textWidth(_ value: String, font: CTFont) -> Double {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: value,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font
                ]))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
    let titleFont = CTFontCreateWithName(FontFace.figtree600.rawValue as CFString, fontSize, nil)
    func text(
        _ value: String, rect: CGRect, color: CGColor, font: CTFont, wrap: Bool = false,
        backing: CGColor? = nil, alignment: Double = 0
    ) {
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
            let measured = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x = rect.minX + max(0, rect.width - measured) * alignment
            if let backing {
                context.setFillColor(backing)
                context.fill(CGRect(x: x, y: y, width: min(rect.width, measured), height: lineHeight))
            }
            context.saveGState()
            context.translateBy(x: x, y: y + CTFontGetAscent(font))
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
    for (index, tick) in layout.ticks.enumerated() where tick.visible {
        context.saveGState()
        context.setAlpha(PlanMetrics.gridOpacity)
        for lane in timelineLanes.indices {
            let x =
                PlanMetrics.gutterWidth + PlanMetrics.laneGap + Double(lane)
                * (geometry.laneWidth + PlanMetrics.laneGap)
            line(x, tick.top, x + geometry.laneWidth, tick.top, token: .border)
        }
        context.restoreGState()
        text(
            day.ticks[index],
            rect: CGRect(
                x: 0, y: tick.top - lineHeight / 2,
                width: PlanMetrics.gutterWidth - PlanMetrics.smallGap, height: lineHeight),
            color: color(.mutedForeground), font: font, alignment: 1)
    }
    let blocks = Dictionary(uniqueKeysWithValues: day.blocks.map { ($0.id, $0) })
    for tile in geometry.tiles {
        guard let block = blocks[tile.blockID] else { continue }
        let style = PlanCategoryStyle(block.block.type)
        let rect = tile.frame
        let radius = block.block.type == .caffeineServing ? min(rect.width, rect.height) / 2 : PlanMetrics.tileRadius
        let path = tilePath(rect, top: tile.continuesBefore ? 0 : radius, bottom: tile.continuesAfter ? 0 : radius)
        context.saveGState()
        context.setAlpha(
            block.status != nil
                ? PlanMetrics.markedOpacity : block.block.priority == .optional ? PlanMetrics.optionalOpacity : 1)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(path)
        context.setFillColor(color(style.fill))
        context.fillPath()
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let pattern = style.pattern {
            context.setAlpha(pattern == .dots ? PlanMetrics.dotOpacity : PlanMetrics.hatchOpacity)
            context.setFillColor(color(style.foreground))
            context.setStrokeColor(color(style.foreground))
            if pattern == .dots {
                for y in stride(from: rect.minY + PlanMetrics.dotStep / 2, to: rect.maxY, by: PlanMetrics.dotStep) {
                    for x in stride(from: rect.minX + PlanMetrics.dotStep / 2, to: rect.maxX, by: PlanMetrics.dotStep) {
                        context.fillEllipse(
                            in: CGRect(
                                x: x - PlanMetrics.dotRadius, y: y - PlanMetrics.dotRadius,
                                width: PlanMetrics.dotRadius * 2, height: PlanMetrics.dotRadius * 2))
                    }
                }
            } else {
                context.setLineWidth(PlanMetrics.patternLine)
                for x in stride(from: rect.minX - rect.height, to: rect.maxX, by: PlanMetrics.patternStep * sqrt(2)) {
                    context.move(to: CGPoint(x: x, y: rect.maxY))
                    context.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                }
                context.strokePath()
            }
            context.setAlpha(1)
        }
        context.restoreGState()
        if block.block.priority == .core {
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setAlpha(PlanMetrics.coreBorderOpacity)
            line(
                rect.minX, rect.minY, rect.minX, rect.maxY, token: .foreground,
                thickness: PlanMetrics.coreBorder * 2)
            context.restoreGState()
        }
        let optional = block.block.priority == .optional
        let outline: ColorToken? =
            optional
            ? .foreground
            : block.block.type == .noCaffeine
                ? .catCaffeine
                : block.block.type == .lightOK ? .catModerateFg : block.block.type == .note ? .border : nil
        if let outline {
            let thickness = block.block.type == .noCaffeine ? PlanMetrics.emphasisBorder : PlanMetrics.border
            let insetRect = rect.insetBy(dx: thickness / 2, dy: thickness / 2)
            context.saveGState()
            context.setAlpha(
                optional ? PlanMetrics.optionalBorderOpacity : block.block.type == .lightOK ? PlanMetrics.tagOpacity : 1
            )
            context.setStrokeColor(color(outline))
            context.setLineWidth(thickness)
            context.setLineDash(phase: 0, lengths: (optional || style.dashed) ? [thickness * 3, thickness * 3] : [])
            context.addPath(
                tilePath(
                    insetRect,
                    top: tile.continuesBefore ? 0 : max(0, radius - thickness / 2),
                    bottom: tile.continuesAfter ? 0 : max(0, radius - thickness / 2)))
            context.strokePath()
            context.restoreGState()
        }
        context.addPath(path)
        context.clip()
        let iconOnly = tile.tiny
        let inset = PlanMetrics.tilePadding
        let iconSize = PlanMetrics.blockIcon * fontSize / PlanMetrics.laneLabelSize
        let contentTop = rect.minY + inset + (tile.continuesBefore ? iconSize + PlanMetrics.smallGap : 0)
        let iconRect = CGRect(
            x: iconOnly ? rect.midX - iconSize / 2 : rect.minX + inset,
            y: iconOnly || block.block.type == .caffeineServing ? rect.midY - iconSize / 2 : contentTop,
            width: iconSize, height: iconSize)
        func drawSymbol(_ name: String, in frame: CGRect) {
            guard let icon = symbols[name] else { return }
            context.saveGState()
            context.translateBy(x: frame.minX, y: frame.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(icon, in: CGRect(origin: .zero, size: frame.size))
            context.restoreGState()
        }
        drawSymbol(block.block.type.rawValue, in: iconRect)
        if block.block.type == .noCaffeine {
            line(
                iconRect.minX, iconRect.maxY, iconRect.maxX, iconRect.minY,
                token: style.foreground, thickness: PlanMetrics.emphasisBorder)
        }
        let faded = block.status != nil || optional
        let textColor = color(faded ? .cardForeground : style.foreground)
        let contentWidth = max(0, rect.width - inset * 2)
        if !iconOnly {
            let titleX = iconRect.maxX + PlanMetrics.smallGap
            let statusWidth = block.status == nil ? 0 : iconSize + PlanMetrics.smallGap
            if block.block.type == .caffeineServing {
                let label = block.title + " · " + block.interval
                text(
                    label,
                    rect: CGRect(
                        x: titleX, y: rect.midY - lineHeight / 2,
                        width: max(0, rect.maxX - inset - statusWidth - titleX), height: lineHeight),
                    color: textColor, font: titleFont, backing: color(style.fill), alignment: 0.5)
            } else {
                text(
                    block.title,
                    rect: CGRect(
                        x: titleX, y: contentTop,
                        width: max(0, rect.maxX - inset - statusWidth - titleX), height: lineHeight),
                    color: textColor, font: titleFont, backing: color(style.fill))
                let intervalTop = contentTop + lineHeight + PlanMetrics.smallGap
                text(
                    block.interval,
                    rect: CGRect(
                        x: rect.minX + inset, y: intervalTop,
                        width: contentWidth, height: min(lineHeight, max(0, rect.maxY - inset - intervalTop))),
                    color: textColor, font: titleFont, backing: color(style.fill))
                let placed = layout.placed.values.joined().first { $0.block.id == block.id }
                if placed?.cols == 1 && rect.height > PlanMetrics.detailsThreshold {
                    let tagTop = intervalTop + lineHeight + PlanMetrics.smallGap
                    let tagWidth = min(contentWidth, textWidth(block.priority, font: tagFont) + inset * 2)
                    let tagRect = CGRect(
                        x: rect.minX + inset, y: tagTop, width: tagWidth,
                        height: tagHeight + PlanMetrics.border * 2)
                    if tagRect.maxY <= rect.maxY - inset {
                        let pill = CGPath(
                            roundedRect: tagRect.insetBy(dx: PlanMetrics.border / 2, dy: PlanMetrics.border / 2),
                            cornerWidth: tagRect.height / 2, cornerHeight: tagRect.height / 2, transform: nil)
                        context.saveGState()
                        context.setAlpha(PlanMetrics.tagOpacity)
                        context.setFillColor(color(.background))
                        context.addPath(pill)
                        context.fillPath()
                        context.setStrokeColor(textColor)
                        context.setLineWidth(PlanMetrics.border)
                        context.setLineDash(
                            phase: 0, lengths: [])
                        context.addPath(pill)
                        context.strokePath()
                        context.restoreGState()
                        text(
                            block.priority, rect: tagRect.insetBy(dx: inset, dy: PlanMetrics.border),
                            color: textColor, font: tagFont)
                        if let reason = block.reason {
                            let y = tagRect.maxY + PlanMetrics.smallGap
                            text(
                                reason,
                                rect: CGRect(
                                    x: rect.minX + inset, y: y, width: contentWidth,
                                    height: min(tagHeight, max(0, rect.maxY - inset - y))),
                                color: textColor, font: tagFont, backing: color(style.fill))
                        }
                    }
                }
            }
        }
        if let status = block.status {
            let frame = CGRect(
                x: rect.maxX - inset - iconSize, y: iconOnly ? rect.minY + inset : contentTop,
                width: iconSize, height: iconSize)
            drawSymbol(status == .done ? "status.done" : "status.skipped", in: frame)
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
        context.endTransparencyLayer()
        context.restoreGState()
    }
    var dividerFrames: [CGRect] = []
    for (index, divider) in layout.dividers.enumerated() {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [PlanMetrics.emphasisBorder, PlanMetrics.smallGap])
        context.setLineWidth(PlanMetrics.emphasisBorder)
        context.setStrokeColor(color(.catTravel))
        context.move(to: CGPoint(x: 0, y: divider.top))
        context.addLine(to: CGPoint(x: geometry.width, y: divider.top))
        context.strokePath()
        context.restoreGState()
        let label = day.dividerLabels[index]
        let rect = CGRect(
            x: PlanMetrics.gutterWidth + PlanMetrics.laneGap,
            y: divider.top - (tagHeight + PlanMetrics.zonePillVerticalPadding * 2) / 2,
            width: min(
                geometry.width - PlanMetrics.gutterWidth - PlanMetrics.laneGap,
                textWidth(label, font: tagFont) + PlanMetrics.zonePillPadding * 2),
            height: tagHeight + PlanMetrics.zonePillVerticalPadding * 2)
        dividerFrames.append(rect)
        context.setFillColor(color(.catTravel))
        context.addPath(
            CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
        context.fillPath()
        text(
            label, rect: rect.insetBy(dx: PlanMetrics.zonePillPadding, dy: PlanMetrics.zonePillVerticalPadding),
            color: color(.catTravelFg), font: tagFont)
    }
    for marker in layout.markers {
        let rect = CGRect(
            x: PlanMetrics.gutterWidth - PlanMetrics.gutterMarkerSize, y: marker.top - PlanMetrics.gutterMarkerSize / 2,
            width: PlanMetrics.gutterMarkerSize, height: PlanMetrics.gutterMarkerSize)
        context.setFillColor(color(.card))
        context.fillEllipse(in: rect)
        text("i", rect: rect.insetBy(dx: PlanMetrics.smallGap, dy: 0), color: color(.foreground), font: titleFont)
    }
    context.endPDFPage()
    context.closePDF()
    guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider)
    else { throw TimelineRenderFailure.document }
    return TimelineDrawing(document: document, byteCount: data.length, dividerFrames: dividerFrames)
}

nonisolated private func tilePath(_ rect: CGRect, top: Double, bottom: Double) -> CGPath {
    let top = min(top, rect.width / 2, rect.height / 2)
    let bottom = min(bottom, rect.width / 2, rect.height / 2)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top), control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
    path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
}

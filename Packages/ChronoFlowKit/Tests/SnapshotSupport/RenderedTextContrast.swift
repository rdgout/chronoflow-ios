import CoreGraphics
import Foundation

public nonisolated enum RenderedTextContrast {
    public struct Measurement {
        public let lines: [Line]
        public let expectedLines: Int
        public var minimum: Double? {
            guard expectedLines > 0, lines.count == expectedLines else { return nil }
            return lines.map(\.minimum).min()
        }
    }

    public struct Line {
        public let frame: CGRect
        public let minimum: Double
        public let maximum: Double
        public let ink: [Double]
    }

    public static func lines(
        raster: SnapshotRaster, frame: CGRect, scale: CGFloat, lineHeight: CGFloat, text: [Double], viewport: CGRect
    ) -> [Line] {
        guard scale.isFinite, scale > 0, lineHeight.isFinite, lineHeight > 0,
            !frame.isEmpty, !frame.isInfinite, !frame.isNull
        else { return [] }
        let count = max(1, Int((frame.height / lineHeight).rounded()))
        return (0..<count).compactMap { index in
            let line = CGRect(
                x: frame.minX, y: frame.minY + CGFloat(index) * lineHeight,
                width: frame.width, height: min(lineHeight, frame.height - CGFloat(index) * lineHeight))
            let visible = line.intersection(viewport)
            guard !visible.isEmpty, !visible.isNull else { return nil }
            guard let bounds = pixelBounds(raster: raster, frame: visible, scale: scale) else { return nil }
            let backgrounds = backgroundSamples(raster: raster, bounds: bounds, text: text)
            guard !backgrounds.isEmpty else { return nil }
            let rows = Dictionary(grouping: backgrounds, by: \.y)
            var inkCount = 0
            var nearTokenCount = 0
            var ink: [Double]?
            for y in bounds.top..<bounds.bottom {
                let row = rows[y] ?? []
                guard let background = row.max(by: { distance($0.rgb, text) < distance($1.rgb, text) })?.rgb else {
                    return nil
                }
                let direction = zip(text, background).map(-)
                let length = direction.reduce(0) { $0 + $1 * $1 }
                for x in bounds.left..<bounds.right {
                    let candidate = pixel(raster, x: x, y: y)
                    let coverage =
                        zip(zip(candidate, background).map(-), direction).reduce(0) { $0 + $1.0 * $1.1 } / length
                    // Include antialiased and dimmed ink, not just the solid centres of glyphs.
                    guard coverage >= 0.1 else { continue }
                    inkCount += 1
                    if distance(candidate, text) < 0.03 {
                        nearTokenCount += 1
                        if ink == nil || luminance(candidate) < luminance(ink!) { ink = candidate }
                    }
                }
            }
            guard let ink, nearTokenCount >= max(3, bounds.bottom - bounds.top),
                Double(nearTokenCount) / Double(inkCount) >= 0.4
            else { return nil }
            let ratios = backgrounds.map { ratio(ink, $0.rgb) }
            return Line(frame: line, minimum: ratios.min()!, maximum: ratios.max()!, ink: ink)
        }
    }

    public static func measure(
        raster: SnapshotRaster, frame: CGRect, scale: CGFloat, lineHeight: CGFloat, text: [Double], viewport: CGRect
    ) -> Measurement {
        let lines = lines(
            raster: raster, frame: frame, scale: scale, lineHeight: lineHeight, text: text, viewport: viewport)
        guard scale.isFinite, scale > 0, lineHeight.isFinite, lineHeight > 0,
            !frame.isEmpty, !frame.isInfinite, !frame.isNull
        else { return Measurement(lines: [], expectedLines: 0) }
        let count = max(1, Int((frame.height / lineHeight).rounded()))
        let expected = (0..<count).filter { index in
            let line = CGRect(
                x: frame.minX, y: frame.minY + CGFloat(index) * lineHeight,
                width: frame.width, height: min(lineHeight, frame.height - CGFloat(index) * lineHeight))
            let visible = line.intersection(viewport)
            return !visible.isEmpty && !visible.isNull
        }.count
        let visible = frame.intersection(viewport)
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(raster.width) / scale, height: CGFloat(raster.height) / scale)
        guard bounds.contains(visible) else { return Measurement(lines: [], expectedLines: expected) }
        return Measurement(lines: lines, expectedLines: expected)
    }

    public static func maximumBackgroundDifference(
        raster: SnapshotRaster, reference: SnapshotRaster, frame: CGRect, scale: CGFloat,
        text: [Double], viewport: CGRect
    ) -> Int? {
        guard raster.width == reference.width, raster.height == reference.height,
            let bounds = pixelBounds(raster: raster, frame: frame.intersection(viewport), scale: scale)
        else { return nil }
        let samples = backgroundSamples(raster: raster, bounds: bounds, text: text)
        guard Set(samples.map(\.y)).count == bounds.bottom - bounds.top else { return nil }
        return samples.map { sample in
            let offset = (sample.y * raster.width + sample.x) * 4
            return (0..<3).map { abs(Int(raster.bytes[offset + $0]) - Int(reference.bytes[offset + $0])) }.max()!
        }.max()
    }

    private struct PixelBounds {
        let left: Int
        let right: Int
        let top: Int
        let bottom: Int
    }

    private struct BackgroundSample {
        let x: Int
        let y: Int
        let rgb: [Double]
    }

    private static func pixelBounds(raster: SnapshotRaster, frame: CGRect, scale: CGFloat) -> PixelBounds? {
        guard scale.isFinite, scale > 0, !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return nil }
        let left = max(0, Int((frame.minX * scale).rounded(.up)))
        let right = min(raster.width, Int((frame.maxX * scale).rounded(.down)))
        let top = max(0, Int((frame.minY * scale).rounded(.up)))
        let bottom = min(raster.height, Int((frame.maxY * scale).rounded(.down)))
        guard left < right, top < bottom else { return nil }
        return PixelBounds(left: left, right: right, top: top, bottom: bottom)
    }

    private static func backgroundSamples(raster: SnapshotRaster, bounds: PixelBounds, text: [Double])
        -> [BackgroundSample]
    {
        var samples: [BackgroundSample] = []
        for y in bounds.top..<bounds.bottom {
            for x in bounds.left..<bounds.right {
                let rgb = pixel(raster, x: x, y: y)
                guard distance(rgb, text) >= 0.1 else { continue }
                // Flat neighbourhoods exclude glyph edges without assuming the screen edge is the backdrop.
                let clean = (max(bounds.top, y - 1)...min(bounds.bottom - 1, y + 1)).allSatisfy { row in
                    (max(bounds.left, x - 1)...min(bounds.right - 1, x + 1)).allSatisfy { column in
                        let offset = (row * raster.width + column) * 4
                        return (0..<3).allSatisfy {
                            abs(Double(raster.bytes[offset + $0]) / 255 - rgb[$0]) <= 2.0 / 255
                        }
                    }
                }
                if clean { samples.append(BackgroundSample(x: x, y: y, rgb: rgb)) }
            }
        }
        return samples
    }

    private static func pixel(_ raster: SnapshotRaster, x: Int, y: Int) -> [Double] {
        let start = (y * raster.width + x) * 4
        return (0..<3).map { Double(raster.bytes[start + $0]) / 255 }
    }

    private static func distance(_ first: [Double], _ second: [Double]) -> Double {
        zip(first, second).map { abs($0 - $1) }.max()!
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        zip(rgb, [0.2126, 0.7152, 0.0722]).reduce(0) {
            let linear = $1.0 <= 0.04045 ? $1.0 / 12.92 : pow(($1.0 + 0.055) / 1.055, 2.4)
            return $0 + linear * $1.1
        }
    }

    public static func ratio(_ first: [Double], _ second: [Double]) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

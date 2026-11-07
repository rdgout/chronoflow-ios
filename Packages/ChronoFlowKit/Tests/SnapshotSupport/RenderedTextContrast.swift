import CoreGraphics
import Foundation

public nonisolated enum RenderedTextContrast {
    public struct Line {
        public let frame: CGRect
        public let minimum: Double
        public let maximum: Double
        public let ink: [Double]
    }

    public static func lines(
        raster: SnapshotRaster, frame: CGRect, scale: CGFloat, lineHeight: CGFloat, text: [Double], viewport: CGRect
    ) -> [Line] {
        let count = max(1, Int((frame.height / lineHeight).rounded()))
        func pixel(_ x: Int, _ y: Int) -> [Double] {
            let start = (y * raster.width + x) * 4
            return (0..<3).map { Double(raster.bytes[start + $0]) / 255 }
        }
        return (0..<count).compactMap { index in
            let line = CGRect(
                x: frame.minX, y: frame.minY + CGFloat(index) * lineHeight,
                width: frame.width, height: min(lineHeight, frame.height - CGFloat(index) * lineHeight))
            let visible = line.intersection(viewport)
            guard !visible.isEmpty, !visible.isNull else { return nil }
            let left = max(0, Int((visible.minX * scale).rounded(.up)))
            let right = min(raster.width, Int((visible.maxX * scale).rounded(.down)))
            let top = max(0, Int((visible.minY * scale).rounded(.up)))
            let bottom = min(raster.height, Int((visible.maxY * scale).rounded(.down)))
            guard left < right, top < bottom else { return nil }
            var backgrounds: [[Double]] = []
            var ink = text
            var distance = Double.infinity
            for y in top..<bottom {
                // CfSky is horizontal-uniform; the unobstructed window edge samples the sky behind the ink.
                let sky = pixel(0, y)
                backgrounds.append(sky)
                for x in left..<right {
                    let candidate = pixel(x, y)
                    let error = zip(candidate, text).map { abs($0 - $1) }.max()!
                    if error < distance {
                        distance = error
                        ink = candidate
                    }
                }
            }
            guard distance < 0.03 else { return nil }
            let ratios = backgrounds.map { ratio(ink, $0) }
            return Line(frame: line, minimum: ratios.min()!, maximum: ratios.max()!, ink: ink)
        }
    }

    public static func ratio(_ first: [Double], _ second: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            zip(rgb, [0.2126, 0.7152, 0.0722]).reduce(0) {
                let linear = $1.0 <= 0.04045 ? $1.0 / 12.92 : pow(($1.0 + 0.055) / 1.055, 2.4)
                return $0 + linear * $1.1
            }
        }
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

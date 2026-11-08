import CoreGraphics
import Foundation

public nonisolated enum AuthSnapshotCapture {
    public static func nativeInputRectsMatch(_ actual: CGRect, _ expected: CGRect, scale: CGFloat) -> Bool {
        guard scale.isFinite, scale > 0 else { return false }
        let components = [
            (actual.origin.x, expected.origin.x), (actual.origin.y, expected.origin.y),
            (actual.width, expected.width), (actual.height, expected.height),
        ]
        return actual.width > 0 && actual.height > 0 && expected.width > 0 && expected.height > 0
            && components.allSatisfy { $0.isFinite && $1.isFinite && abs($0 * scale - $1 * scale) <= 1 }
    }

    public static func pixelsMatchOutsideNativeInput(
        _ actual: SnapshotRaster, _ expected: SnapshotRaster, input: CGRect, referenceInput: CGRect, scale: CGFloat
    ) -> Bool {
        guard actual.width == expected.width, actual.height == expected.height,
            nativeInputRectsMatch(input, referenceInput, scale: scale)
        else { return false }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(actual.width) / scale, height: CGFloat(actual.height) / scale)
        guard bounds.contains(input), bounds.contains(referenceInput) else { return false }
        let mask = input.union(referenceInput)
        let left = max(0, Int((mask.minX * scale - 1).rounded(.down)))
        let right = min(actual.width, Int((mask.maxX * scale + 1).rounded(.up)))
        let top = max(0, Int((mask.minY * scale - 1).rounded(.down)))
        let bottom = min(actual.height, Int((mask.maxY * scale + 1).rounded(.up)))
        for y in 0..<actual.height {
            for x in 0..<actual.width where y < top || y >= bottom || x < left || x >= right {
                let index = (y * actual.width + x) * 4
                for channel in 0..<4 where actual.bytes[index + channel] != expected.bytes[index + channel] {
                    return false
                }
            }
        }
        return true
    }

    public static func failure(
        raster: SnapshotRaster, size: CGSize, scale: CGFloat, viewport: CGRect,
        frames: [String: CGRect], required: Set<String>
    ) -> String? {
        guard raster.width == Int((size.width * scale).rounded()),
            raster.height == Int((size.height * scale).rounded())
        else { return "Auth capture dimensions are clipped or use the wrong display scale" }
        guard stride(from: 3, to: raster.bytes.count, by: 4).allSatisfy({ raster.bytes[$0] == 255 }) else {
            return "Auth capture contains transparent pixels"
        }
        guard required.isSubset(of: Set(frames.keys)) else { return "Auth capture is missing measured content" }
        let tolerance = 1 / scale
        for name in required {
            guard let frame = frames[name], !frame.isNull, !frame.isInfinite,
                frame.minX.isFinite, frame.minY.isFinite, frame.maxX.isFinite, frame.maxY.isFinite,
                frame.width > 0, frame.height > 0,
                frame.minX >= viewport.minX - tolerance, frame.maxX <= viewport.maxX + tolerance
            else { return "Auth capture clips \(name) horizontally" }
        }
        for name in ["brand", "heading"] {
            guard let frame = frames[name], viewport.insetBy(dx: -tolerance, dy: -tolerance).contains(frame) else {
                return "Auth capture clips \(name) vertically"
            }
            guard hasInk(raster, in: frame, scale: scale) else { return "Auth capture has blank \(name) content" }
        }
        return nil
    }

    public static func verify(
        png: Data, size: CGSize, scale: CGFloat, viewport: CGRect, frames: [String: CGRect], required: Set<String>,
        reference: URL, record: Bool
    ) throws -> String? {
        let sample = try SnapshotReference.Sample(png: png)
        if let failure = failure(
            raster: sample.raster, size: size, scale: scale, viewport: viewport, frames: frames, required: required)
        {
            return failure
        }
        return try SnapshotReference.verify(sample: sample, reference: reference, record: record)
    }

    public static func hasInk(_ raster: SnapshotRaster, in frame: CGRect, scale: CGFloat) -> Bool {
        let left = max(0, Int((frame.minX * scale).rounded(.up)))
        let right = min(raster.width - 1, Int((frame.maxX * scale).rounded(.down)))
        let top = max(0, Int((frame.minY * scale).rounded(.up)))
        let bottom = min(raster.height, Int((frame.maxY * scale).rounded(.down)))
        guard left < right, top < bottom else { return false }
        var edges = 0
        for y in top..<bottom {
            for x in left..<right {
                let index = (y * raster.width + x) * 4
                if (0..<3).contains(where: {
                    abs(Int(raster.bytes[index + $0]) - Int(raster.bytes[index + 4 + $0])) > 12
                }) {
                    edges += 1
                    if edges >= 4 { return true }
                }
            }
        }
        return false
    }
}

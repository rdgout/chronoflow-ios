import CoreGraphics
import Foundation

public nonisolated enum AuthSnapshotCapture {
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

    private static func hasInk(_ raster: SnapshotRaster, in frame: CGRect, scale: CGFloat) -> Bool {
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

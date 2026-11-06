import CoreGraphics
import Foundation
import ImageIO

public nonisolated struct SnapshotRaster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return false }
        return lhs.bytes.withUnsafeBytes { left in
            rhs.bytes.withUnsafeBytes { right in
                memcmp(left.baseAddress!, right.baseAddress!, left.count) == 0
            }
        }
    }

    public init(png: Data) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw RasterError.invalidPNG }
        try self.init(image: image)
    }

    public init(image: CGImage) throws {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw RasterError.noContext }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    enum RasterError: Error { case invalidPNG, noContext }
}

public nonisolated enum SnapshotReference {
    public enum Content { case visible, fullyTransparent }

    public struct Sample {
        public let png: Data
        public let raster: SnapshotRaster

        public init(png: Data) throws {
            self.png = png
            raster = try SnapshotRaster(png: png)
        }
    }

    public static func verify(png: Data, reference: URL, record: Bool, content: Content = .visible) throws -> String? {
        try verify(sample: Sample(png: png), reference: reference, record: record, content: content)
    }

    public static func verify(sample: Sample, reference: URL, record: Bool, content: Content = .visible) throws
        -> String?
    {
        let actual = sample.raster
        switch content {
        case .visible:
            guard WelcomeSnapshotPixels.hasVisibleVariation(actual.bytes) else {
                return "Welcome capture is uniform or transparent; refusing snapshot"
            }
        case .fullyTransparent:
            guard WelcomeSnapshotPixels.isFullyTransparent(actual.bytes) else {
                return "Exited splash still contains visible pixels; refusing snapshot"
            }
        }
        if record {
            try FileManager.default.createDirectory(
                at: reference.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sample.png.write(to: reference, options: .atomic)
            return "Record mode is on. Recorded \(reference.lastPathComponent)"
        }
        guard FileManager.default.fileExists(atPath: reference.path) else {
            return "Missing Welcome reference: \(reference.path). Record explicitly with SNAPSHOT_RECORD=1."
        }
        let expected = try SnapshotRaster(png: Data(contentsOf: reference))
        guard actual == expected else {
            let first = zip(actual.bytes, expected.bytes).enumerated().first { $0.element.0 != $0.element.1 }
            let detail =
                first.map { "byte \($0.offset): actual \($0.element.0), expected \($0.element.1)" }
                ?? "dimensions differ"
            return "Welcome pixels differ from \(reference.path) (\(detail))"
        }
        return nil
    }
}

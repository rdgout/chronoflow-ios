import CoreGraphics
import Foundation
import ImageIO
import SnapshotSupport
import Testing
import UniformTypeIdentifiers

@Suite struct SnapshotReferenceTests {
    @Test func encodedMetadataAndCompressionDoNotChangeComparison() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../build/SnapshotReferenceTests/\(UUID().uuidString)").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = directory.appendingPathComponent("fixture.png")
        let first = try fixture(comment: "first process", compressed: true)
        let second = try fixture(comment: "after other tests", compressed: false)
        #expect(first != second)
        #expect(try SnapshotRaster(png: first) == SnapshotRaster(png: second))
        #expect(
            try SnapshotReference.verify(png: first, reference: reference, record: false)?.hasPrefix("Missing") == true)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(
            try SnapshotReference.verify(png: first, reference: reference, record: true)?.hasPrefix("Record mode")
                == true)
        for sample in [first, second] {
            #expect(try SnapshotReference.verify(png: sample, reference: reference, record: false) == nil)
        }
        let mutation = try fixture(comment: "changed pixel", compressed: true, changed: true)
        #expect(
            try SnapshotReference.verify(png: mutation, reference: reference, record: false)?.contains("pixels differ")
                == true)
        #expect(try Data(contentsOf: reference) == first)
    }

    @Test func rejectsInvalidPNG() {
        #expect(throws: (any Error).self) { try SnapshotRaster(png: Data("invalid".utf8)) }
    }

    private func fixture(comment: String, compressed: Bool, changed: Bool = false) throws -> Data {
        var bytes: [UInt8] = [0, 0, 0, 255, 128, 128, 128, 255, 0, 0, 0, 0, 12, 24, 36, 100]
        if changed { bytes[4] += 1 }
        let image = try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            return try #require(context.makeImage())
        }
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image,
            [
                kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: comment],
                kCGImagePropertyPNGCompressionFilter: compressed ? IMAGEIO_PNG_FILTER_PAETH : IMAGEIO_PNG_FILTER_NONE,
            ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

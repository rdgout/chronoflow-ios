import CoreGraphics
import Foundation
import ImageIO
import SnapshotSupport
import Testing
import UniformTypeIdentifiers

@Suite struct SnapshotReferenceTests {
    @Test func missingReferencesNameThePathWithoutAssumingAScreenOrRecording() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../build/SnapshotReferenceTests/\(UUID().uuidString)").standardizedFileURL
        let sample = try SnapshotReference.Sample(png: fixture(comment: "missing", compressed: true))
        for path in ["Welcome/fixture.png", "Auth/SignIn/en.png", "Auth/TwoFactor/code.png"] {
            let reference = directory.appendingPathComponent(path)
            #expect(
                try SnapshotReference.verify(sample: sample, reference: reference, record: false)
                    == "Missing snapshot reference: \(reference.path). Record explicitly with SNAPSHOT_RECORD=1.")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

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
        for png in [first, second] {
            let sample = try SnapshotReference.Sample(png: png)
            #expect(try SnapshotReference.verify(sample: sample, reference: reference, record: false) == nil)
            let duplicate = directory.appendingPathComponent("equivalent.png")
            #expect(
                try SnapshotReference.verify(sample: sample, reference: duplicate, record: true)?.hasPrefix(
                    "Record mode") == true)
            #expect(try SnapshotReference.verify(sample: sample, reference: duplicate, record: false) == nil)
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

    @Test func transparentExitIsExplicitAndRejectsAnyVisiblePixel() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../build/SnapshotReferenceTests/\(UUID().uuidString)").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: directory) }
        let reference = directory.appendingPathComponent("exited.png")
        let transparent = try fixture(comment: "fully exited", compressed: true, transparent: true)
        #expect(
            try SnapshotReference.verify(png: transparent, reference: reference, record: true)?
                .contains("uniform or transparent") == true)
        #expect(!FileManager.default.fileExists(atPath: reference.path))
        #expect(
            try SnapshotReference.verify(
                png: transparent, reference: reference, record: true, content: .fullyTransparent)?
                .hasPrefix("Record mode") == true)
        #expect(
            try SnapshotReference.verify(
                png: transparent, reference: reference, record: false, content: .fullyTransparent) == nil)
        let visible = try fixture(comment: "visible", compressed: true)
        #expect(
            try SnapshotReference.verify(png: visible, reference: reference, record: true, content: .fullyTransparent)?
                .contains("still contains visible pixels") == true)
        #expect(try Data(contentsOf: reference) == transparent)
        #expect(!WelcomeSnapshotPixels.isFullyTransparent([]))
        #expect(!WelcomeSnapshotPixels.isFullyTransparent([0, 0, 0]))
        #expect(!WelcomeSnapshotPixels.isFullyTransparent([0, 0, 0, 1]))
        #expect(WelcomeSnapshotPixels.isFullyTransparent([255, 255, 255, 0]))
    }

    private func fixture(comment: String, compressed: Bool, changed: Bool = false, transparent: Bool = false) throws
        -> Data
    {
        var bytes: [UInt8] = [0, 0, 0, 255, 128, 128, 128, 255, 0, 0, 0, 0, 12, 24, 36, 100]
        if changed { bytes[4] += 1 }
        if transparent { bytes = Array(repeating: 0, count: bytes.count) }
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

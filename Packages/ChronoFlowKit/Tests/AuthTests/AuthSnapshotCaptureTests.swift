import CoreGraphics
import Foundation
import ImageIO
import SnapshotSupport
import Testing
import UniformTypeIdentifiers

struct AuthSnapshotCaptureTests {
    private let size = CGSize(width: 40, height: 60)
    private let viewport = CGRect(x: 2, y: 2, width: 36, height: 56)
    private var frames: [String: CGRect] {
        [
            "brand": CGRect(x: 4, y: 4, width: 32, height: 10),
            "heading": CGRect(x: 4, y: 18, width: 32, height: 10),
            "card": CGRect(x: 4, y: 32, width: 32, height: 50),
        ]
    }

    @Test func nativeInputToleranceAllowsOnlyOneDevicePixelInEachComponent() {
        for scale: CGFloat in [2, 3] {
            let reference = CGRect(x: 48, y: 474, width: 279, height: 25)
            #expect(AuthSnapshotCapture.nativeInputRectsMatch(reference, reference, scale: scale))
            for component in 0..<4 {
                for delta in [-1, 1, -1.5, 1.5] {
                    var values: [CGFloat] = [48, 474, 279, 25]
                    values[component] += delta / scale
                    let actual = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
                    #expect(
                        AuthSnapshotCapture.nativeInputRectsMatch(actual, reference, scale: scale) == (abs(delta) == 1))
                }
            }
            for invalid in [CGRect.null, .infinite, .zero] {
                #expect(!AuthSnapshotCapture.nativeInputRectsMatch(invalid, reference, scale: scale))
                #expect(!AuthSnapshotCapture.nativeInputRectsMatch(reference, invalid, scale: scale))
            }
        }
        for scale: CGFloat in [0, -1, .infinity, .nan] {
            #expect(!AuthSnapshotCapture.nativeInputRectsMatch(viewport, viewport, scale: scale))
        }
    }

    @Test func nativeInputPixelMaskKeepsEveryOutsidePixelAndChannelExact() throws {
        let reference = try SnapshotRaster(png: png())
        for scale: CGFloat in [2, 3] {
            let referenceInput = CGRect(x: 8 / scale, y: 8 / scale, width: 8 / scale, height: 8 / scale)
            let input = CGRect(x: 9 / scale, y: 9 / scale, width: 9 / scale, height: 7 / scale)
            func matches(_ actual: SnapshotRaster, input: CGRect = input) -> Bool {
                AuthSnapshotCapture.pixelsMatchOutsideNativeInput(
                    actual, reference, input: input, referenceInput: referenceInput, scale: scale)
            }
            let masked = try SnapshotRaster(
                png: png { bytes in
                    for y in 7..<17 {
                        for x in 7..<19 {
                            for channel in 0..<3 { bytes[(y * 40 + x) * 4 + channel] = 100 }
                        }
                    }
                })
            #expect(masked != reference)
            #expect(matches(masked))
            for (x, y) in [(6, 8), (19, 8), (8, 6), (8, 17), (0, 0), (39, 59)] {
                for channel in 0..<4 {
                    let changed = try SnapshotRaster(
                        png: png { bytes in bytes[(y * 40 + x) * 4 + channel] ^= 1 })
                    #expect(changed != reference)
                    #expect(!matches(changed))
                }
            }
            var oversized = input
            oversized.size.width += 1 / scale
            #expect(!matches(reference, input: oversized))
            #expect(!matches(reference, input: .null))
            #expect(
                !AuthSnapshotCapture.pixelsMatchOutsideNativeInput(
                    reference, reference, input: referenceInput.offsetBy(dx: -20, dy: 0),
                    referenceInput: referenceInput.offsetBy(dx: -20, dy: 0), scale: scale))
        }
    }

    @Test func rejectsBlankGradientTransparentWrongScaleAndClippedContent() throws {
        let raster = try SnapshotRaster(png: png())
        #expect(failure(raster) == nil)
        #expect(try failure(SnapshotRaster(png: png(ink: false)))?.contains("blank") == true)
        #expect(try failure(SnapshotRaster(png: png(alpha: 0)))?.contains("transparent") == true)
        #expect(failure(raster, scale: 2)?.contains("dimensions") == true)
        for name in ["brand", "heading", "card"] {
            var missing = frames
            missing[name] = nil
            #expect(failure(raster, frames: missing)?.contains("missing") == true)
            var clipped = frames
            clipped[name]?.origin.x = 0
            #expect(failure(raster, frames: clipped)?.contains("horizontally") == true)
        }
        var clipped = frames
        clipped["heading"]?.origin.y = -1
        #expect(failure(raster, frames: clipped)?.contains("vertically") == true)
        clipped = frames
        clipped["card"]?.size.height = 0
        #expect(failure(raster, frames: clipped) != nil)
    }

    @Test func elementInkRejectsTheSkyEvenWhenAnotherElementHasInk() throws {
        let raster = try SnapshotRaster(png: png())
        #expect(AuthSnapshotCapture.hasInk(raster, in: frames["heading"]!, scale: 1))
        #expect(!AuthSnapshotCapture.hasInk(raster, in: CGRect(x: 4, y: 32, width: 32, height: 10), scale: 1))
        #expect(try !AuthSnapshotCapture.hasInk(SnapshotRaster(png: png(ink: false)), in: frames["heading"]!, scale: 1))
    }

    @Test func lineContrastUsesRenderedInkAndRejectsBlankLines() throws {
        let frame = frames["heading"]!
        let text = [Double](repeating: 240.0 / 255, count: 3)
        let lines = try RenderedTextContrast.lines(
            raster: SnapshotRaster(png: png()), frame: frame, scale: 1, lineHeight: frame.height,
            text: text, viewport: viewport)
        #expect(lines.count == 1)
        #expect(lines.first?.ink == text)
        #expect(lines.first!.minimum > 4.5)
        #expect(
            try RenderedTextContrast.lines(
                raster: SnapshotRaster(png: png(ink: false)), frame: frame, scale: 1, lineHeight: frame.height,
                text: text, viewport: viewport
            ).isEmpty)
        #expect(RenderedTextContrast.ratio([0, 0, 0], [1, 1, 1]) == 21)
        #expect(RenderedTextContrast.ratio(text, text) == 1)
    }

    @Test func contrastMinimumRequiresEveryVisibleLineAndRejectsLowContrast() throws {
        let frame = CGRect(x: 4, y: 4, width: 32, height: 24)
        func measure(_ png: Data, ink: Double = 240.0 / 255, visible: CGRect? = nil) throws
            -> RenderedTextContrast.Measurement
        {
            RenderedTextContrast.measure(
                raster: try SnapshotRaster(png: png), frame: frame, scale: 1, lineHeight: 12,
                text: [Double](repeating: ink, count: 3), viewport: visible ?? viewport)
        }
        let passing = try measure(png())
        #expect(passing.expectedLines == 2)
        #expect(passing.minimum! >= 4.5)
        let missing = try measure(png(headingInk: false))
        #expect(missing.lines.count == 1)
        #expect(missing.expectedLines == 2)
        #expect(missing.minimum == nil)
        #expect(try measure(png(ink: false)).minimum == nil)
        let failing = try measure(png(foreground: 120), ink: 120.0 / 255)
        #expect(failing.lines.count == 2)
        #expect(failing.minimum! < 4.5)
        #expect(try measure(png(), visible: CGRect(x: 0, y: 0, width: 40, height: 16)).expectedLines == 1)
        #expect(try measure(png(), visible: CGRect(x: 0, y: 30, width: 40, height: 20)).minimum == nil)
    }

    @Test func contrastSamplesTheWorstLocalBackdropInsteadOfTheScreenEdge() throws {
        let frame = CGRect(x: 4, y: 4, width: 32, height: 12)
        let text = [Double](repeating: 240.0 / 255, count: 3)
        let raster = try SnapshotRaster(
            png: png { bytes in
                for y in 4..<16 {
                    for x in 28..<36 {
                        for channel in 0..<3 { bytes[(y * 40 + x) * 4 + channel] = 185 }
                    }
                }
            })
        let measurement = RenderedTextContrast.measure(
            raster: raster, frame: frame, scale: 1, lineHeight: 12, text: text, viewport: viewport)
        let minimum = try #require(measurement.minimum)
        #expect(minimum < 4.5)
        #expect(abs(minimum - RenderedTextContrast.ratio(text, [Double](repeating: 185.0 / 255, count: 3))) < 0.001)
        let reference = try SnapshotRaster(png: png())
        #expect(
            RenderedTextContrast.maximumBackgroundDifference(
                raster: reference, reference: reference, frame: frame, scale: 1, text: text, viewport: viewport) == 0)
        let difference = try #require(
            RenderedTextContrast.maximumBackgroundDifference(
                raster: raster, reference: reference, frame: frame, scale: 1, text: text, viewport: viewport))
        #expect(difference > 2)
    }

    @Test func contrastRejectsMostlyDimmedInkEvenWithSomeOpaqueTokenPixels() throws {
        let frame = CGRect(x: 4, y: 4, width: 32, height: 12)
        for opaqueColumns in [1, 6] {
            let raster = try SnapshotRaster(
                png: png { bytes in
                    for y in 6..<12 {
                        for x in 8..<24 where x >= 8 + opaqueColumns || y != 6 && opaqueColumns == 1 {
                            for channel in 0..<3 { bytes[(y * 40 + x) * 4 + channel] = 100 }
                        }
                    }
                })
            #expect(
                RenderedTextContrast.measure(
                    raster: raster, frame: frame, scale: 1, lineHeight: 12,
                    text: [Double](repeating: 240.0 / 255, count: 3), viewport: viewport
                ).minimum == nil)
        }
    }

    @Test func contrastAcceptsAntialiasedInkButRequiresCleanLocalBackground() throws {
        let frame = CGRect(x: 4, y: 4, width: 32, height: 12)
        let text = [Double](repeating: 240.0 / 255, count: 3)
        let antialiased = try SnapshotRaster(
            png: png { bytes in
                for y in 6..<12 {
                    for x in [8, 23] {
                        for channel in 0..<3 { bytes[(y * 40 + x) * 4 + channel] = 125 }
                    }
                }
            })
        #expect(
            try #require(
                RenderedTextContrast.measure(
                    raster: antialiased, frame: frame, scale: 1, lineHeight: 12, text: text, viewport: viewport
                ).minimum
            ) >= 4.5)
        let noBackground = try SnapshotRaster(
            png: png { bytes in
                for y in 4..<16 {
                    for x in 4..<36 {
                        for channel in 0..<3 { bytes[(y * 40 + x) * 4 + channel] = 240 }
                    }
                }
            })
        #expect(
            RenderedTextContrast.measure(
                raster: noBackground, frame: frame, scale: 1, lineHeight: 12, text: text, viewport: viewport
            ).minimum == nil)
        #expect(
            RenderedTextContrast.maximumBackgroundDifference(
                raster: noBackground, reference: antialiased, frame: frame, scale: 1, text: text, viewport: viewport)
                == nil)
    }

    @Test func rejectsBlankRecordingBeforeWritingAndKeepsComparisonReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "auth-capture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = root.appending(path: "capture.png")
        func verify(_ png: Data, record: Bool) throws -> String? {
            try AuthSnapshotCapture.verify(
                png: png, size: size, scale: 1, viewport: viewport, frames: frames, required: Set(frames.keys),
                reference: reference, record: record)
        }
        #expect(try verify(png(ink: false), record: true)?.contains("blank") == true)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try verify(png(), record: false)?.hasPrefix("Missing snapshot reference:") == true)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try verify(png(), record: true)?.hasPrefix("Record mode is on.") == true)
        let original = try Data(contentsOf: reference)
        #expect(try verify(png(), record: false) == nil)
        #expect(try verify(png(ink: false), record: true)?.contains("blank") == true)
        #expect(try Data(contentsOf: reference) == original)
    }

    private func failure(_ raster: SnapshotRaster, scale: CGFloat = 1, frames: [String: CGRect]? = nil) -> String? {
        AuthSnapshotCapture.failure(
            raster: raster, size: size, scale: scale, viewport: viewport, frames: frames ?? self.frames,
            required: Set(self.frames.keys))
    }

    private func png(
        ink: Bool = true, alpha: UInt8 = 255, headingInk: Bool = true, foreground: UInt8 = 240,
        modify: ((inout [UInt8]) -> Void)? = nil
    ) throws
        -> Data
    {
        var bytes = [UInt8](repeating: 0, count: 40 * 60 * 4)
        for y in 0..<60 {
            for x in 0..<40 {
                let index = (y * 40 + x) * 4
                let marked =
                    ink && (8..<24).contains(x) && ((6..<12).contains(y) || (headingInk && (20..<26).contains(y)))
                for channel in 0..<3 { bytes[index + channel] = marked ? foreground : UInt8(y) }
                bytes[index + 3] = alpha
            }
        }
        modify?(&bytes)
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(
            CGImage(
                width: 40, height: 60, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 160,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return result as Data
    }
}

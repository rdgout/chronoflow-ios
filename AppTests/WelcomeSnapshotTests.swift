#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import Testing
    import UIKit

    @testable import ChronoFlow
    @testable import Welcome

    @Suite(.serialized) @MainActor struct WelcomeSnapshotTests {
        @Test func frozenIntro() async throws {
            try await FontRegistry.register()
            let start = ContinuousClock.now
            var captures = 0
            for device in try SnapshotDevice.all() {
                let host = WelcomeTestWindow(style: .light, device: device)
                defer { host.close() }
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        var landed: SnapshotReference.Sample?
                        for time in try device.coverage.introTimes {
                            let sample: SnapshotReference.Sample
                            if time >= 3200, let landed {
                                sample = landed
                            } else {
                                func capture() async throws -> UIImage {
                                    let intro = LaunchIntro(
                                        start: .milliseconds(2300), clock: ManualLaunchClock(),
                                        frozenTime: .milliseconds(time))
                                    host.configure(style: style, language: language, intro: intro)
                                    let image = try await host.layout()
                                    try #require(intro.hasPlayed)
                                    captures += 1
                                    return image
                                }
                                let image = try await capture()
                                if time >= 2450 {
                                    let repeated = try await capture()
                                    let actual = try SnapshotRaster(image: #require(image.cgImage))
                                    let expected = try SnapshotRaster(image: #require(repeated.cgImage))
                                    try #require(
                                        actual == expected,
                                        "Fresh frozen roots differ at \(time), \(device.alias), \(style), \(language); refusing snapshot"
                                    )
                                }
                                sample = try SnapshotReference.Sample(png: #require(image.pngData()))
                                if time >= 3200 { landed = sample }
                            }
                            let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                            let result = try verifyWelcomeSnapshot(
                                of: sample,
                                named: "\(device.name)-\(style == .dark ? "dark" : "light")-\(language)-\(time)",
                                record: record, testName: "frozenIntro")
                            if record {
                                #expect(result?.hasPrefix("Record mode is on.") == true, "\(result ?? "")")
                            } else {
                                #expect(result == nil, "\(result ?? "")")
                            }
                        }
                    }
                }
            }
            print("frozenIntro: \(captures) captures, \(start.duration(to: .now))")
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["CF_INTRO_ORDER"] != nil))
        func frozenIntroOrderIndependence() async throws {
            let order = try #require(ProcessInfo.processInfo.environment["CF_INTRO_ORDER"])
            try #require(["fresh", "warm"].contains(order))
            if order == "warm" {
                try await finalWelcome()
                try await frozenIntro()
            }
            try await FontRegistry.register()
            let intro = LaunchIntro(
                start: .milliseconds(2300), clock: ManualLaunchClock(), frozenTime: .milliseconds(2700))
            let device = try #require(SnapshotDevice.all().first { $0.alias == "17e" })
            let host = WelcomeTestWindow(style: .light, language: "en", intro: intro, device: device)
            defer { host.close() }
            try await host.layout()
            let image = try host.image()
            let png = try #require(image.pngData())
            let model = try #require(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"])
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let directory = root.appendingPathComponent("build/test-results/intro-order/\(model)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(order).png"), options: .atomic)
            let memory = pixels(image)
            let decoded = try SnapshotRaster(png: png).bytes
            let different = zip(memory, decoded).filter { $0 != $1 }.count
            print(
                "Frozen intro \(order): memory-vs-PNG differing channels=\(different), bits=\(image.cgImage?.bitsPerComponent ?? 0), space=\(String(describing: image.cgImage?.colorSpace))"
            )
            let name = "\(device.name)-light-en-2700"
            #expect(try verifyWelcomeSnapshot(of: image, named: name, record: false, testName: "frozenIntro") == nil)
            if order == "fresh" {
                let recorded = try verifyWelcomeSnapshot(
                    of: image, named: "order", record: true, testName: "frame", directory: directory)
                #expect(recorded?.hasPrefix("Record mode") == true)
            } else {
                #expect(
                    try verifyWelcomeSnapshot(
                        of: image, named: "order", record: false, testName: "frame", directory: directory) == nil)
            }
        }

        @Test func finalWelcome() async throws {
            try await FontRegistry.register()
            let start = ContinuousClock.now
            var captures = 0
            for device in try SnapshotDevice.all() {
                let host = WelcomeTestWindow(style: .light, device: device)
                defer { host.close() }
                var variants: [String: SnapshotRaster] = [:]
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        var images: [DynamicTypeSize: SnapshotReference.Sample] = [:]
                        var cappedFrames: [WelcomeElement: CGRect] = [:]
                        for typeSize in try profileSizes(device.coverage) {
                            let effective = min(typeSize, ContentSizeCap.maximum)
                            let sample: SnapshotReference.Sample
                            if let cached = images[effective],
                                !(device.alias == "17e" && typeSize > ContentSizeCap.maximum)
                            {
                                sample = cached
                            } else {
                                host.configure(style: style, language: language, typeSize: typeSize)
                                let image = try await host.layout()
                                sample = try SnapshotReference.Sample(png: #require(image.pngData()))
                                captures += 1
                                try host.assertHorizontalInsets()
                                let brand = try #require(host.frames[.brand])
                                let eyebrow = try #require(host.frames[.eyebrow])
                                let headline = try #require(host.frames[.headline])
                                #expect(brand.maxY < eyebrow.minY && eyebrow.maxY < headline.minY)
                                if typeSize == .xxLarge { cappedFrames = host.frames }
                                if typeSize > ContentSizeCap.maximum {
                                    #expect(sample.raster == images[.xxLarge]?.raster, "Root cap pixels: \(typeSize)")
                                    #expect(host.frames == cappedFrames, "Root cap frames: \(typeSize)")
                                } else {
                                    images[effective] = sample
                                }
                                if typeSize == .large || typeSize == .xxLarge {
                                    variants["\(style.rawValue)-\(language)-\(typeSize)"] = sample.raster
                                }
                            }
                            let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                            let result = try verifyWelcomeSnapshot(
                                of: sample,
                                named: "\(device.name)-\(style == .dark ? "dark" : "light")-\(language)-\(typeSize)",
                                record: record, testName: "finalWelcome")
                            if record {
                                #expect(result?.hasPrefix("Record mode is on.") == true, "\(result ?? "")")
                            } else {
                                #expect(result == nil, "\(result ?? "")")
                            }
                        }
                    }
                }
                for size in [DynamicTypeSize.large, .xxLarge] {
                    for language in ["en", "nl"] {
                        #expect(
                            WelcomeSnapshotPixels.differ(
                                try #require(variants["\(UIUserInterfaceStyle.light.rawValue)-\(language)-\(size)"])
                                    .bytes,
                                try #require(variants["\(UIUserInterfaceStyle.dark.rawValue)-\(language)-\(size)"])
                                    .bytes))
                    }
                    for style in [UIUserInterfaceStyle.light, .dark] {
                        #expect(
                            WelcomeSnapshotPixels.differ(
                                try #require(variants["\(style.rawValue)-en-\(size)"]).bytes,
                                try #require(variants["\(style.rawValue)-nl-\(size)"]).bytes))
                    }
                }
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        #expect(
                            WelcomeSnapshotPixels.differ(
                                try #require(variants["\(style.rawValue)-\(language)-large"]).bytes,
                                try #require(variants["\(style.rawValue)-\(language)-xxLarge"]).bytes))
                    }
                }
            }
            print("finalWelcome: \(captures) captures, \(start.duration(to: .now))")
        }
    }
#endif

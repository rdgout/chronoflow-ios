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
                try await accessibilitySizesRenderTheSameWelcomeAsXXLarge()
                try await trackedEyebrowKeepsItsIntrinsicWidthThroughTheCap()
                try await positiveLeadingStylesKeepTheirExistingPixels()
                explicitLocalesResolveTheCatalog()
                try await renderedWelcomeContainsTextAndChangesWithAppearanceAndLanguage()
                try await laterAppearanceAndReduceMotionShowTheFinalScreen()
                try await frozenIntroPixelsStayFixedAcrossClockAndRenderPasses()
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

        @Test func frozenIntroPixelsStayFixedAcrossClockAndRenderPasses() async throws {
            try await FontRegistry.register()
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for time in try SnapshotProfile.current().introTimes {
                        var previousMount: [UInt8]?
                        for _ in 0..<(time == 2400 ? 10 : 2) {
                            let clock = ManualLaunchClock()
                            let intro = LaunchIntro(
                                start: .milliseconds(2300), clock: clock, frozenTime: .milliseconds(time))
                            let host = WelcomeTestWindow(style: style, language: language, intro: intro)
                            defer { host.close() }
                            try await host.layout()
                            #expect(intro.hasPlayed)
                            let current = pixels(try host.image())
                            if let previousMount {
                                #expect(current == previousMount, "Frozen pixels changed across mounts at \(time)")
                            }
                            previousMount = current
                            let reference = current
                            let frames = host.frames
                            for advance in [10, 20, 30] {
                                clock.advance(to: .seconds(advance))
                                try await host.layout()
                                #expect(try pixels(host.image()) == reference, "Frozen \(time), \(style), \(language)")
                                #expect(host.frames == frames)
                                #expect(!host.hasAnimations, "Frozen intro must not install live animations")
                            }
                        }
                    }
                }
            }
        }

        @Test func laterAppearanceAndReduceMotionShowTheFinalScreen() async throws {
            try await FontRegistry.register()
            let intro = LaunchIntro(
                start: .milliseconds(2300), clock: ManualLaunchClock(), frozenTime: .milliseconds(2400))
            let first = WelcomeTestWindow(style: .light, intro: intro)
            try await first.layout()
            #expect(intro.hasPlayed)
            first.close()
            let later = WelcomeTestWindow(style: .light, intro: intro)
            defer { later.close() }
            try await later.layout()
            let reference = WelcomeTestWindow(style: .light)
            defer { reference.close() }
            try await reference.layout()
            #expect(try pixels(later.image()) == pixels(reference.image()))
            let reducedIntro = LaunchIntro(start: .seconds(30), clock: ManualLaunchClock())
            let reduced = WelcomeTestWindow(style: .light, intro: reducedIntro, reduceMotion: true)
            defer { reduced.close() }
            try await reduced.layout()
            #expect(!reducedIntro.hasPlayed)
            #expect(try pixels(reduced.image()) == pixels(reference.image()))
        }

        @Test func finalWelcome() async throws {
            try await FontRegistry.register()
            let start = ContinuousClock.now
            var captures = 0
            for device in try SnapshotDevice.all() {
                let host = WelcomeTestWindow(style: .light, device: device)
                defer { host.close() }
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        var images: [DynamicTypeSize: SnapshotReference.Sample] = [:]
                        for typeSize in try profileSizes(device.coverage) {
                            let effective = min(typeSize, ContentSizeCap.maximum)
                            let sample: SnapshotReference.Sample
                            if let cached = images[effective] {
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
                                images[effective] = sample
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
            }
            print("finalWelcome: \(captures) captures, \(start.duration(to: .now))")
        }

        @Test func accessibilitySizesRenderTheSameWelcomeAsXXLarge() async throws {
            try await FontRegistry.register()
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    let capped = WelcomeTestWindow(style: style, language: language, typeSize: .xxLarge)
                    try await capped.layout()
                    let reference = try pixels(capped.image())
                    let frames = capped.frames
                    capped.close()
                    for size in DynamicTypeSize.allCases where size > ContentSizeCap.maximum {
                        let host = WelcomeTestWindow(style: style, language: language, typeSize: size)
                        defer { host.close() }
                        try await host.layout()
                        #expect(try pixels(host.image()) == reference)
                        #expect(host.frames == frames)
                    }
                    let normal = WelcomeTestWindow(style: style, language: language)
                    defer { normal.close() }
                    try await normal.layout()
                    #expect(try WelcomeSnapshotPixels.differ(pixels(normal.image()), reference))
                }
            }
        }

        @Test func trackedEyebrowKeepsItsIntrinsicWidthThroughTheCap() async throws {
            try await FontRegistry.register()
            for language in ["en", "nl"] {
                for size in try profileSizes() {
                    let host = WelcomeTestWindow(style: .light, language: language, typeSize: size)
                    defer { host.close() }
                    try await host.layout()
                    let font = Typography.eyebrow.uiFont(
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size)))
                    let text = WelcomeCopy.string("Jet-lag planner", locale: Locale(identifier: language)).uppercased()
                    let natural = NSAttributedString(
                        string: text,
                        attributes: [
                            .font: font, .kern: Typography.eyebrow.tracking * font.pointSize / Typography.eyebrow.size,
                        ]
                    ).size()
                    let frame = try #require(host.frames[.eyebrow])
                    #expect(frame.width >= natural.width - 0.5, "\(language), \(size): \(frame), \(natural)")
                    #expect(frame.height >= natural.height - 0.5)
                    try host.assertHorizontalInsets()
                }
            }
        }

        @Test func positiveLeadingStylesKeepTheirExistingPixels() async throws {
            try await FontRegistry.register()
            for appearance in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for size in [DynamicTypeSize.large, .xxLarge] {
                        let host = WelcomeTestWindow(style: appearance, language: language, typeSize: size)
                        defer { host.close() }
                        let styles: [(String, Typography.Style, ColorToken)] = [
                            ("ChronoFlow", Typography.welcomeWordmark, .skyTitle),
                            ("Jet-lag planner", Typography.eyebrow, .dawn),
                            (
                                "Tell us your flights and how you sleep. You get a day-by-day plan for sleep, light and caffeine that helps your body clock shift.",
                                Typography.copy, .skyCopy
                            ),
                        ]
                        var reference: [UInt8]?
                        for legacy in [true, false] {
                            host.controller.rootView = AnyView(
                                VStack(alignment: .leading) {
                                    ForEach(styles.indices, id: \.self) { index in
                                        let (key, style, color) = styles[index]
                                        let text = WelcomeCopy.string(key, locale: Locale(identifier: language))
                                        let font = style.uiFont(
                                            compatibleWith: UITraitCollection(
                                                preferredContentSizeCategory: UIContentSizeCategory(size)))
                                        let ratio = font.pointSize / style.size
                                        let leading = (style.lineHeight ?? font.lineHeight) * ratio - font.lineHeight
                                        if legacy {
                                            Text(verbatim: text)
                                                .font(.custom(style.face.rawValue, fixedSize: font.pointSize))
                                                .tracking(style.tracking * ratio)
                                                .lineSpacing(leading)
                                                .padding(.vertical, leading / 2)
                                                .fixedSize(horizontal: style == Typography.eyebrow, vertical: true)
                                                .foregroundStyle(color.color)
                                        } else {
                                            WelcomeText(text, style: style, color: color)
                                        }
                                    }
                                }
                                .padding(WelcomeTokens.gutter)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(CfSky())
                                .environment(\.dynamicTypeSize, size)
                                .environment(\.colorScheme, appearance == .dark ? .dark : .light))
                            host.window.layoutIfNeeded()
                            try await Task.sleep(for: .milliseconds(50))
                            let rendered = try pixels(host.image())
                            if let reference { #expect(rendered == reference) } else { reference = rendered }
                        }
                    }
                }
            }
        }

        @Test func explicitLocalesResolveTheCatalog() {
            for language in ["en", "nl"] {
                let locale = Locale(identifier: language)
                #expect(WelcomeCopy.string("ChronoFlow", locale: locale) == "ChronoFlow")
                #expect(
                    WelcomeCopy.string("Jet-lag planner", locale: locale).uppercased(with: locale)
                        == (language == "nl" ? "JETLAGPLANNER" : "JET-LAG PLANNER"))
            }
            #expect(WelcomeCopy.string("Plan my trip", locale: Locale(identifier: "en")) == "Plan my trip")
            #expect(WelcomeCopy.string("Plan my trip", locale: Locale(identifier: "nl")) == "Plan mijn reis")
            #expect(WelcomeCopy.string("Sign in", locale: Locale(identifier: "nl")) == "Inloggen")
        }

        @Test func renderedWelcomeContainsTextAndChangesWithAppearanceAndLanguage() async throws {
            try await FontRegistry.register()
            for typeSize in [DynamicTypeSize.large, .xxLarge] {
                var rendered: [String: [UInt8]] = [:]
                for style in [UIUserInterfaceStyle.light, .dark] {
                    for language in ["en", "nl"] {
                        let host = WelcomeTestWindow(style: style, language: language, typeSize: typeSize)
                        defer { host.close() }
                        try await host.layout()
                        let image = try host.image()
                        rendered["\(style.rawValue)-\(language)"] = pixels(image)
                    }
                }
                for language in ["en", "nl"] {
                    #expect(
                        WelcomeSnapshotPixels.differ(
                            try #require(rendered["\(UIUserInterfaceStyle.light.rawValue)-\(language)"]),
                            try #require(rendered["\(UIUserInterfaceStyle.dark.rawValue)-\(language)"])))
                }
                for style in [UIUserInterfaceStyle.light, .dark] {
                    #expect(
                        WelcomeSnapshotPixels.differ(
                            try #require(rendered["\(style.rawValue)-en"]),
                            try #require(rendered["\(style.rawValue)-nl"])))
                }
            }
        }

    }

    @MainActor private func profileSizes(_ profile: SnapshotProfile? = nil) throws -> [DynamicTypeSize] {
        let names = try (profile ?? SnapshotProfile.current()).dynamicType
        return DynamicTypeSize.allCases.filter { names.contains(String(describing: $0)) }
    }

    @MainActor final class WelcomeTestWindow {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
        var frames: [WelcomeElement: CGRect] = [:]
        private(set) var moonAnchor = MoonAnchorStore()
        let container: SnapshotContainer
        let scale: CGFloat
        private let fixture: SnapshotDevice?
        private var expectedIntro: LaunchIntro?
        private var revision = 0

        init(
            style: UIUserInterfaceStyle, language: String = "en", typeSize: DynamicTypeSize = .large,
            size: CGSize? = nil, intro: LaunchIntro? = nil, reduceMotion: Bool = false, device: SnapshotDevice? = nil
        ) {
            fixture = device
            container = SnapshotContainer(size: device?.size ?? size, insets: device?.insets, scale: device?.scale)
            window = container.window
            scale = container.scale
            window.maximumContentSizeCategory = ContentSizeCap.maximumCategory
            window.overrideUserInterfaceStyle = style
            controller = UIHostingController(rootView: AnyView(EmptyView()))
            if device != nil { controller.safeAreaRegions = [] }
            container.host(controller)
            configure(style: style, language: language, typeSize: typeSize, intro: intro, reduceMotion: reduceMotion)
        }

        func configure(
            style: UIUserInterfaceStyle, language: String = "en", typeSize: DynamicTypeSize = .large,
            intro: LaunchIntro? = nil, reduceMotion: Bool = false
        ) {
            expectedIntro = reduceMotion ? nil : intro
            frames = [:]
            moonAnchor = MoonAnchorStore()
            revision += 1
            window.overrideUserInterfaceStyle = style
            controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
            controller.traitOverrides.displayScale = scale
            controller.overrideUserInterfaceStyle = style
            controller.rootView = AnyView(
                WelcomeView(safeAreaInsets: container.insets) { [weak self, revision] element, rect in
                    guard let self, self.revision == revision else { return }
                    self.frames[element] = rect
                }
                .dynamicTypeSize(...ContentSizeCap.maximum)
                .environment(\.locale, Locale(identifier: language))
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.displayScale, scale)
                .environment(\.moonAnchorStore, moonAnchor)
                .environment(\.launchIntro, intro)
                .environment(\.forcesReduceMotion, reduceMotion)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .id(revision))
        }

        @discardableResult func layout() async throws -> UIImage {
            var previous: SnapshotRaster?
            var previousFrames: [WelcomeElement: CGRect] = [:]
            // A main-queue turn commits onAppear and representable updates before the pixel comparison.
            for _ in 0..<8 {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                let image = try image()
                let current = try SnapshotRaster(image: #require(image.cgImage))
                let ready = frames.count == WelcomeElement.allCases.count && expectedIntro?.hasPlayed != false
                if ready && current == previous && frames == previousFrames {
                    try #require(
                        WelcomeSnapshotPixels.hasVisibleVariation(current.bytes),
                        "Welcome capture is uniform or transparent; refusing snapshot")
                    if let fixture {
                        #expect(window.bounds.size == fixture.size)
                        #expect(controller.view.bounds.size == fixture.size)
                        #expect(controller.safeAreaRegions.isEmpty)
                        #expect(controller.traitCollection.displayScale == fixture.scale)
                        let geometry = WelcomeGeometry(size: fixture.size, insets: fixture.insets)
                        let brand = try #require(frames[.brand])
                        #expect(abs(brand.minX - geometry.leading) < 0.5)
                        #expect(abs(brand.minY - geometry.top) < 0.5)
                    }
                    #expect(window.isKeyWindow)
                    #expect(controller.view.window === window)
                    return image
                }
                previous = current
                previousFrames = frames
            }
            throw CaptureError.didNotSettle
        }

        private enum CaptureError: Error { case didNotSettle }

        var hasAnimations: Bool {
            func animated(_ layer: CALayer) -> Bool {
                !(layer.animationKeys() ?? []).isEmpty || (layer.sublayers ?? []).contains(where: animated)
            }
            return animated(window.layer)
        }

        func assertHorizontalInsets() throws {
            let native = controller.view.safeAreaInsets
            let insets =
                fixture?.insets ?? .init(top: native.top, left: native.left, bottom: native.bottom, right: native.right)
            let content = MoonTarget.contentBounds(size: window.bounds.size, safeAreaInsets: insets)
            for element in WelcomeElement.allCases {
                let frame = try #require(frames[element])
                #expect(frame.minX >= content.minX - 0.5, "\(element): \(frame), \(content)")
                #expect(frame.maxX <= content.maxX + 0.5, "\(element): \(frame), \(content)")
            }
        }

        func image() throws -> UIImage {
            window.makeKeyAndVisible()
            UIView.performWithoutAnimation {
                @MainActor
                func layout(_ view: UIView) {
                    view.layoutIfNeeded()
                    view.subviews.forEach(layout)
                }
                func display(_ layer: CALayer) {
                    layer.displayIfNeeded()
                    layer.sublayers?.forEach(display)
                }
                layout(window)
                display(window.layer)
                CATransaction.flush()
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            format.preferredRange = .standard
            var rendered = false
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(rendered, "drawHierarchy did not capture the Welcome window")
            return image
        }

        func close() {
            container.close()
        }
    }
#endif

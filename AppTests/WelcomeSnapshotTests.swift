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
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for time in [2400, 2450, 2700, 3200, 3300] {
                        func capture() async throws -> (image: UIImage, size: CGSize, scale: CGFloat) {
                            let intro = LaunchIntro(
                                start: .milliseconds(2300), clock: ManualLaunchClock(), frozenTime: .milliseconds(time))
                            let host = WelcomeTestWindow(style: style, language: language, intro: intro)
                            defer { host.close() }
                            try await host.layout()
                            #expect(intro.hasPlayed)
                            return (try host.image(), host.window.bounds.size, host.window.screen.scale)
                        }
                        let sample = try await capture()
                        if time >= 2450 {
                            let repeated = try await capture()
                            try #require(
                                pixels(sample.image) == pixels(repeated.image),
                                "Fresh frozen hosts differ at \(time), \(style), \(language); refusing snapshot")
                        }
                        let size = sample.size
                        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iPhone"
                        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                        let result = try verifyWelcomeSnapshot(
                            of: sample.image,
                            named:
                                "\(device)-\(Int(size.width))x\(Int(size.height))-\(Int(sample.scale))x-\(style == .dark ? "dark" : "light")-\(language)-\(time)",
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

        @Test func frozenIntroPixelsStayFixedAcrossClockAndRenderPasses() async throws {
            try await FontRegistry.register()
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for time in [2400, 2450, 2700, 3200, 3300] {
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
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for typeSize in [DynamicTypeSize.large, .xxLarge] {
                        let host = WelcomeTestWindow(style: style, language: language, typeSize: typeSize)
                        defer { host.close() }
                        try await host.layout()
                        try host.assertHorizontalInsets()
                        let image = try host.image()
                        let size = host.window.bounds.size
                        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iPhone"
                        let name = "\(device)-\(Int(size.width))x\(Int(size.height))-\(Int(host.window.screen.scale))x"
                        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                        let result = try verifyWelcomeSnapshot(
                            of: image,
                            named: "\(name)-\(style == .dark ? "dark" : "light")-\(language)-\(typeSize)",
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

        @Test func accessibilitySizesRenderTheSameWelcomeAsXXLarge() async throws {
            try await FontRegistry.register()
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    let capped = WelcomeTestWindow(style: style, language: language, typeSize: .xxLarge)
                    try await capped.layout()
                    let reference = try pixels(capped.image())
                    let frames = capped.frames
                    capped.close()
                    for size in [DynamicTypeSize.xxxLarge, .accessibility5] {
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
                for size in DynamicTypeSize.allCases {
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

        @Test func boardGeometryAndAsymmetricInsets() async throws {
            try await FontRegistry.register()
            let board = WelcomeTestWindow(style: .light, size: CGSize(width: 390, height: 844))
            defer { board.close() }
            board.controller.safeAreaRegions = []
            try await board.layout()
            let expected: [(WelcomeElement, CGFloat, CGFloat?)] = [
                (.brand, 64, 28), (.eyebrow, 164, 16),
                (.headline, 196, 3 * CGFloat(try #require(Typography.headline.lineHeight))),
                (.plan, 688, 52), (.signIn, 752, 52),
            ]
            for (element, top, height) in expected {
                let rect = try #require(board.frames[element])
                #expect(abs(rect.minY - top) <= 0.5, "\(element): \(rect)")
                #expect(abs(rect.minX - 24) <= 0.5)
                if let height { #expect(abs(rect.height - height) <= 0.5, "\(element): \(rect)") }
            }
            for language in ["en", "nl"] {
                for size in DynamicTypeSize.allCases {
                    let host = WelcomeTestWindow(style: .dark, language: language, typeSize: size)
                    defer { host.close() }
                    host.controller.additionalSafeAreaInsets = UIEdgeInsets(top: 7, left: 19, bottom: 11, right: 31)
                    try await host.layout()
                    try host.assertHorizontalInsets()
                    let headline = try #require(host.frames[.headline])
                    let card = try #require(host.frames[.copy])
                    #expect(card.minY - headline.maxY >= 23.5)
                    #expect(try #require(host.frames[.signIn]).height >= 52)
                }
            }
        }

        @Test func headlineUsesTheScaledBoardPitchInBothLanguages() async throws {
            try await FontRegistry.register()
            for language in ["en", "nl"] {
                for size in [DynamicTypeSize.large, .xxLarge, .accessibility5] {
                    let host = WelcomeTestWindow(style: .light, language: language, typeSize: size)
                    defer { host.close() }
                    try await host.layout()
                    let headline = try #require(host.frames[.headline])
                    let font = Typography.headline.uiFont(
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size)))
                    let pitch = try #require(Typography.headline.lineHeight) * font.pointSize / Typography.headline.size
                    func labels(in view: UIView) -> [UILabel] {
                        view.subviews.flatMap { child in (child as? UILabel).map { [$0] } ?? labels(in: child) }
                    }
                    let lines = labels(in: host.controller.view).sorted {
                        $0.convert($0.bounds, to: host.window).minY < $1.convert($1.bounds, to: host.window).minY
                    }
                    #expect(lines.count > 1)
                    #expect(abs(headline.height - CGFloat(lines.count) * pitch) <= 0.5)
                    for (first, second) in zip(lines, lines.dropFirst()) {
                        let a = first.convert(first.bounds, to: host.window)
                        let b = second.convert(second.bounds, to: host.window)
                        #expect(abs(b.minY - a.minY - pitch) <= 0.5, "\(language), \(size): \(a), \(b)")
                    }
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

    @MainActor final class WelcomeTestWindow {
        let window: UIWindow
        let controller: UIHostingController<AnyView>
        var frames: [WelcomeElement: CGRect] = [:]
        private weak var previousKeyWindow: UIWindow?
        private let expectedIntro: LaunchIntro?

        init(
            style: UIUserInterfaceStyle, language: String = "en", typeSize: DynamicTypeSize = .large,
            size: CGSize? = nil, intro: LaunchIntro? = nil, reduceMotion: Bool = false
        ) {
            expectedIntro = reduceMotion ? nil : intro
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                previousKeyWindow = scene.keyWindow
                window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
            } else {
                preconditionFailure("Welcome snapshots require an app-hosted window scene")
            }
            if let size { window.frame = CGRect(origin: .zero, size: size) }
            window.maximumContentSizeCategory = ContentSizeCap.maximumCategory
            window.overrideUserInterfaceStyle = style
            controller = UIHostingController(rootView: AnyView(EmptyView()))
            controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
            controller.traitOverrides.displayScale = window.screen.scale
            controller.overrideUserInterfaceStyle = style
            controller.rootView = AnyView(
                WelcomeView { [weak self] element, rect in self?.frames[element] = rect }
                    .dynamicTypeSize(...ContentSizeCap.maximum)
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.displayScale, window.screen.scale)
                    .environment(\.launchIntro, intro)
                    .environment(\.forcesReduceMotion, reduceMotion)
                    .environment(\.colorScheme, style == .dark ? .dark : .light))
            window.rootViewController = controller
            window.makeKeyAndVisible()
        }

        func layout() async throws {
            window.makeKeyAndVisible()
            window.setNeedsLayout()
            window.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for _ in 0..<100 where frames.count < WelcomeElement.allCases.count || expectedIntro?.hasPlayed == false {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(frames.count == WelcomeElement.allCases.count)
            try #require(expectedIntro?.hasPlayed != false)
            // Geometry callbacks precede UIViewRepresentable label drawing and the render-server commit.
            var previous: [UInt8]?
            var previousFrames: [WelcomeElement: CGRect] = [:]
            var matchingPasses = 0
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(10))
                let current = try pixels(image())
                matchingPasses = current == previous && frames == previousFrames ? matchingPasses + 1 : 0
                if matchingPasses == 2 { break }
                previous = current
                previousFrames = frames
            }
            try #require(matchingPasses == 2, "Welcome pixels/layout did not settle within the capture bound")
            #expect(window.isKeyWindow)
            #expect(controller.view.window === window)
        }

        var hasAnimations: Bool {
            func animated(_ layer: CALayer) -> Bool {
                !(layer.animationKeys() ?? []).isEmpty || (layer.sublayers ?? []).contains(where: animated)
            }
            return animated(window.layer)
        }

        func assertHorizontalInsets() throws {
            let insets = controller.view.safeAreaInsets
            let content = MoonTarget.contentBounds(
                size: window.bounds.size,
                safeAreaInsets: .init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right))
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
            format.scale = window.screen.scale
            format.opaque = false
            format.preferredRange = .standard
            var rendered = false
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(rendered, "drawHierarchy did not capture the Welcome window")
            try #require(
                WelcomeSnapshotPixels.hasVisibleVariation(pixels(image)),
                "Welcome capture is uniform or transparent; refusing snapshot")
            return image
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
    }
#endif

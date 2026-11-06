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
                        let intro = LaunchIntro(
                            start: .milliseconds(2300), clock: ManualLaunchClock(), frozenTime: .milliseconds(time))
                        let host = WelcomeTestWindow(style: style, language: language, intro: intro)
                        defer { host.close() }
                        try await host.layout()
                        #expect(intro.hasPlayed)
                        let size = host.window.bounds.size
                        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iPhone"
                        let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"
                        let result = try verifyWelcomeSnapshot(
                            of: try host.image(),
                            named:
                                "\(device)-\(Int(size.width))x\(Int(size.height))-\(Int(host.window.screen.scale))x-\(style == .dark ? "dark" : "light")-\(language)-\(time)",
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
                (.brand, 64, 28), (.eyebrow, 164, 16), (.headline, 196, nil),
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
            #expect(frames.count == WelcomeElement.allCases.count)
            #expect(expectedIntro?.hasPlayed != false)
            try await Task.sleep(for: .milliseconds(50))
            controller.view.layoutIfNeeded()
            CATransaction.flush()
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
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
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

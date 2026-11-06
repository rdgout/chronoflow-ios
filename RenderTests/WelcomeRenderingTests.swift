#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import Testing
    import UIKit

    @testable import ChronoFlow
    @testable import Welcome

    @Suite(.serialized) @MainActor struct WelcomeRenderingTests {
        @Test func frozenIntroPixelsStayFixedAcrossClockAndRenderPasses() async throws {
            try await FontRegistry.register()
            for style in [UIUserInterfaceStyle.light, .dark] {
                for language in ["en", "nl"] {
                    for time in try SnapshotProfile.current().introTimes {
                        var previousMount: SnapshotRaster?
                        for _ in 0..<2 {
                            let clock = ManualLaunchClock()
                            let intro = LaunchIntro(
                                start: .milliseconds(2300), clock: clock, frozenTime: .milliseconds(time))
                            let host = WelcomeTestWindow(style: style, language: language, intro: intro)
                            defer { host.close() }
                            let image = try await host.layout()
                            #expect(intro.hasPlayed)
                            let current = try SnapshotRaster(image: #require(image.cgImage))
                            if let previousMount {
                                #expect(current == previousMount, "Frozen pixels changed across mounts at \(time)")
                            }
                            previousMount = current
                            let reference = current
                            let frames = host.frames
                            for advance in [10, 20, 30] {
                                clock.advance(to: .seconds(advance))
                                let image = try await host.layout()
                                #expect(
                                    try SnapshotRaster(image: #require(image.cgImage)) == reference,
                                    "Frozen \(time), \(style), \(language)")
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
    }
#endif

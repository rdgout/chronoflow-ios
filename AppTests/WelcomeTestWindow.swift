#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI
    import Testing
    import UIKit

    @testable import ChronoFlow
    @testable import Welcome

    @MainActor func profileSizes(_ profile: SnapshotProfile? = nil) throws -> [DynamicTypeSize] {
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
            // The render-server gradient dither varies across processes; render the committed layer tree on the CPU.
            return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
                window.layer.render(in: context.cgContext)
            }
        }

        func close() {
            container.close()
        }
    }
#endif

import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor final class AuthTestHost {
    let controller: UIHostingController<AnyView>
    let container: SnapshotContainer
    let scale: CGFloat
    var prepareCapture: (UIWindow) -> Void = { _ in }
    private var revision = 0
    private var checkedRenderRevision: Int?
    var window: UIWindow { container.window }

    init<V: View>(
        _ view: V, size: CGSize, insets: UIEdgeInsets = .zero, style: UIUserInterfaceStyle = .light,
        language: String = "en", category: UIContentSizeCategory = .large, scale: CGFloat? = nil
    ) throws {
        container = SnapshotContainer(
            size: size, insets: .init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right),
            scale: scale)
        self.scale = container.scale
        controller = UIHostingController(rootView: AnyView(EmptyView()))
        controller.safeAreaRegions = []
        ContentSizeCap.apply(to: container.root, in: window)
        container.host(controller)
        configure(view, style: style, language: language, category: category)
    }

    func configure<V: View>(
        _ view: V, style: UIUserInterfaceStyle = .light, language: String = "en",
        category: UIContentSizeCategory = .large
    ) {
        revision += 1
        let insets = container.insets ?? .init(top: 0, left: 0, bottom: 0, right: 0)
        window.overrideUserInterfaceStyle = style
        controller.overrideUserInterfaceStyle = style
        // Inject the system preference above the window cap, as in the app.
        window.traitOverrides.preferredContentSizeCategory = category
        controller.traitOverrides.displayScale = scale
        controller.rootView = AnyView(
            view.dynamicTypeSize(...ContentSizeCap.maximum)
                .environment(\.locale, Locale(identifier: language))
                .environment(\.dynamicTypeSize, ContentSizeCap.clamp(DynamicTypeSize(category) ?? .large))
                .environment(\.displayScale, scale)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .environment(
                    \.planPageSafeBounds,
                    CGRect(
                        x: insets.left, y: insets.top,
                        width: window.bounds.width - insets.left - insets.right,
                        height: window.bounds.height - insets.top - insets.bottom)
                )
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: insets.bottom) }
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: insets.left) }
                .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: insets.right) }
                .id(revision))
    }

    func settleLayout(measuring frames: () -> [CGRect]) async throws {
        window.makeKeyAndVisible()
        var previous: [CGRect] = []
        var matches = 0
        let deadline = ContinuousClock.now + .seconds(5)
        for _ in 1...12 {
            try await Task.sleep(for: .milliseconds(10))
            guard ContinuousClock.now < deadline else { break }
            layout()
            let current = frames().sorted {
                [$0.minX, $0.minY, $0.width, $0.height].lexicographicallyPrecedes(
                    [$1.minX, $1.minY, $1.width, $1.height])
            }
            matches = !current.isEmpty && current == previous ? matches + 1 : 0
            if matches == 2 {
                if checkedRenderRevision != revision {
                    let raster = try SnapshotRaster(image: XCTUnwrap(image().cgImage))
                    XCTAssertTrue(WelcomeSnapshotPixels.hasVisibleVariation(raster.bytes))
                    checkedRenderRevision = revision
                }
                XCTAssertTrue(window.isKeyWindow)
                XCTAssertEqual(controller.view.bounds.size, window.bounds.size)
                XCTAssertTrue(controller.safeAreaRegions.isEmpty)
                XCTAssertEqual(controller.traitCollection.displayScale, scale)
                return
            }
            previous = current
        }
        throw CaptureFailure.didNotSettle("Layout: revision \(revision), size \(window.bounds.size)")
    }

    private func layout() {
        UIView.performWithoutAnimation {
            @MainActor func visit(_ view: UIView) {
                view.layoutIfNeeded()
                view.subviews.forEach(visit)
            }
            visit(window)
        }
    }

    func settle() async throws {
        var previous: SnapshotRaster?
        var matches = 0
        let deadline = ContinuousClock.now + .seconds(5)
        for attempt in 1...12 {
            try await Task.sleep(for: .milliseconds(10))
            guard ContinuousClock.now < deadline else {
                throw CaptureFailure.didNotSettle("5 s deadline, attempt \(attempt), revision \(revision)")
            }
            let current = try SnapshotRaster(image: XCTUnwrap(image().cgImage))
            matches = current == previous ? matches + 1 : 0
            if matches == 2 {
                XCTAssertTrue(WelcomeSnapshotPixels.hasVisibleVariation(current.bytes))
                XCTAssertEqual(controller.view.bounds.size, window.bounds.size)
                XCTAssertTrue(controller.safeAreaRegions.isEmpty)
                XCTAssertEqual(controller.traitCollection.displayScale, scale)
                XCTAssertTrue(window.isKeyWindow)
                return
            }
            previous = current
        }
        throw CaptureFailure.didNotSettle("12 captures, revision \(revision), size \(window.bounds.size)")
    }

    nonisolated static func registerFonts() async throws {
        let completed = XCTestExpectation(description: "Auth fonts registered off the main thread")
        let registration = Task {
            defer { completed.fulfill() }
            try await FontRegistry.register()
        }
        guard await XCTWaiter.fulfillment(of: [completed], timeout: 10) == .completed else {
            registration.cancel()
            throw CaptureFailure.fontRegistrationTimedOut
        }
        try await registration.value
    }

    private enum CaptureFailure: Error {
        case didNotSettle(String)
        case fontRegistrationTimedOut
    }

    func image() throws -> UIImage {
        window.makeKeyAndVisible()
        UIView.performWithoutAnimation {
            func display(_ layer: CALayer) {
                layer.displayIfNeeded()
                layer.sublayers?.forEach(display)
            }
            layout()
            prepareCapture(window)
            display(window.layer)
            CATransaction.flush()
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        // Match Welcome's CPU capture; render-server gradient dither varies between processes.
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    func close() { container.close() }
}

nonisolated struct AuthDeviceFixture {
    let name: String
    let size: CGSize
    let insets: UIEdgeInsets
    var scale: CGFloat = 3
    var device: SnapshotDevice?
    var snapshotName: String { device?.name ?? name }

    @MainActor var categories: [UIContentSizeCategory] {
        get throws {
            guard let device else { return [.large, .extraExtraLarge] }
            return try profileSizes(device.coverage).map(UIContentSizeCategory.init)
        }
    }

    static func layoutStressProfiles() throws -> [Self] {
        let fixtures = try all()
        let se = try XCTUnwrap(fixtures.first { $0.name == "se" })
        let duo = try XCTUnwrap(fixtures.first { $0.name == "duo" })
        return [
            se,
            .init(
                name: "duo-asymmetric", size: duo.size,
                insets: UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 62), scale: duo.scale),
        ]
    }

    static func authSnapshotProfiles() throws -> [Self] {
        try all().filter { ["17e", "se", "duo"].contains($0.name) }
    }

    @MainActor var authSnapshotVariants: [(UIUserInterfaceStyle, String, UIContentSizeCategory)] {
        [UIUserInterfaceStyle.light, .dark].flatMap { style in
            ["en", "nl"].map { (style, $0, UIContentSizeCategory.large) }
        } + (name == "17e" ? [(.light, "en", .extraExtraLarge)] : [])
    }

    static func all() throws -> [Self] {
        [.init(name: "board", size: CGSize(width: 375, height: 812), insets: .zero)]
            + (try SnapshotDevice.all()).map { device in
                .init(
                    name: device.alias, size: device.size,
                    insets: UIEdgeInsets(
                        top: device.insets.top, left: device.insets.left, bottom: device.insets.bottom,
                        right: device.insets.right), scale: device.scale, device: device)
            }
    }
}

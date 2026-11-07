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
    private var revision = 0
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
        window.maximumContentSizeCategory = ContentSizeCap.maximumCategory
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
                .environment(\.dynamicTypeSize, DynamicTypeSize(category) ?? .large)
                .environment(\.displayScale, scale)
                .environment(\.colorScheme, style == .dark ? .dark : .light)
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: insets.bottom) }
                .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: insets.left) }
                .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: insets.right) }
                .id(revision))
    }

    func settle() async throws {
        var previous: SnapshotRaster?
        var matches = 0
        for _ in 0..<12 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
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
        throw CaptureFailure.didNotSettle
    }

    private enum CaptureFailure: Error { case didNotSettle }

    func image() throws -> UIImage {
        window.makeKeyAndVisible()
        UIView.performWithoutAnimation {
            @MainActor func layout(_ view: UIView) {
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

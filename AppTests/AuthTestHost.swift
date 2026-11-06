import AppCore
import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

@MainActor final class AuthTestHost {
    let controller: UIHostingController<AnyView>
    let host: LaunchTestHost
    let scale: CGFloat
    var window: UIWindow { host.window }

    init<V: View>(
        _ view: V, size: CGSize, insets: UIEdgeInsets = .zero, style: UIUserInterfaceStyle = .light,
        language: String = "en", category: UIContentSizeCategory = .large, scale: CGFloat? = nil
    ) throws {
        controller = UIHostingController(
            rootView: AnyView(
                view.environment(\.locale, Locale(identifier: language))
                    .dynamicTypeSize(...ContentSizeCap.maximum)
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: insets.bottom) }
                    .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: insets.left) }
                    .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: insets.right) }))
        controller.safeAreaRegions = []
        controller.traitOverrides.preferredContentSizeCategory = category
        host = try LaunchTestHost(controller: controller, style: style)
        self.scale = scale ?? host.window.screen.scale
        controller.traitOverrides.displayScale = self.scale
        window.frame = CGRect(origin: .zero, size: size)
        window.maximumContentSizeCategory = ContentSizeCap.maximumCategory
        window.makeKeyAndVisible()
    }
    func settle() async throws {
        var previous: Data?
        var matches = 0
        for _ in 0..<100 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            let png = try XCTUnwrap(image().pngData())
            matches = png == previous ? matches + 1 : 0
            if matches == 2 { return }
            previous = png
        }
        XCTFail("Auth capture did not settle")
    }
    func image() throws -> UIImage {
        CATransaction.flush()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .standard
        var captured = false
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(captured)
        let png = try XCTUnwrap(image.pngData())
        XCTAssertTrue(WelcomeSnapshotPixels.hasVisibleVariation(try SnapshotRaster(png: png).bytes))
        return image
    }
    func close() { host.close() }
}

nonisolated struct AuthDeviceFixture {
    let name: String
    let size: CGSize
    let insets: UIEdgeInsets
    var scale: CGFloat = 3
    static var all: [Self] {
        [
            .init(name: "board", size: CGSize(width: 375, height: 812), insets: .zero),
            .init(
                name: "se", size: CGSize(width: 375, height: 667),
                insets: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0), scale: 2),
            .init(
                name: "17e", size: CGSize(width: 390, height: 844),
                insets: UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)),
            .init(
                name: "17", size: CGSize(width: 402, height: 874),
                insets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
            .init(
                name: "air", size: CGSize(width: 420, height: 912),
                insets: UIEdgeInsets(top: 68, left: 0, bottom: 34, right: 0)),
            .init(
                name: "18pro", size: CGSize(width: 402, height: 874),
                insets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
            .init(
                name: "18promax", size: CGSize(width: 440, height: 956),
                insets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)),
            .init(
                name: "duo", size: CGSize(width: 466, height: 678),
                insets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 19)),
        ]
    }
}
